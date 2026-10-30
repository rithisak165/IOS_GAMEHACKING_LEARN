#import "SceneViewController.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <SceneKit/SceneKit.h>
#import <Foundation/Foundation.h>
#include <vector>
#include <cmath>
#include <string>

// Dear ImGui
#include "IMGUI/imgui.h"
#include "IMGUI/imgui_internal.h"
#include "IMGUI/imgui_impl_metal.h"

// Telemetry & ESP Settings
struct ESPOptions {
    bool   bMasterESP      = true;
    bool   bSkeleton       = true;
    bool   bBox            = true;
    bool   bSnaplines      = true;
    bool   bDistance       = true;
    bool   bHealth         = true;
    bool   bFOVCircle      = true;
    float  fovRadius       = 140.0f;
    float  headOffset      = 1.85f;
    float  boxWidthScale   = 0.45f;
    ImVec4 skeletonColor   = ImVec4(0.0f, 1.0f, 0.9f, 1.0f); // Bright Cyan
    ImVec4 boxColor        = ImVec4(1.0f, 0.2f, 0.2f, 1.0f); // Bright Red
    ImVec4 lineColor       = ImVec4(1.0f, 0.9f, 0.1f, 0.9f); // Gold Yellow
    ImVec4 fovColor        = ImVec4(1.0f, 1.0f, 1.0f, 0.4f); // Subtle White
};

static ESPOptions g_Settings;
static bool g_ShowMenu = true;

// Structure to track 3D target dummies
struct DummyTarget {
    std::string name;
    SCNNode *rootNode;
    float health;
    float maxHealth;
};

// Forward declaration of touch-intercepting MTKView
@interface OverlayTouchView : MTKView
@end

@implementation OverlayTouchView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!g_ShowMenu || !ImGui::GetCurrentContext()) {
        return NO; // When menu is closed, touch goes directly to 3D camera controls
    }

    ImGuiContext *g = ImGui::GetCurrentContext();
    ImVec2 pt = ImVec2(point.x, point.y);

    // Check if touch is within any open ImGui window
    for (int i = 0; i < g->Windows.Size; i++) {
        ImGuiWindow *window = g->Windows[i];
        if (!window || !window->WasActive || window->Hidden) continue;
        if (window->Flags & ImGuiWindowFlags_NoInputs) continue;

        if (pt.x >= window->Pos.x && pt.x <= (window->Pos.x + window->Size.x) &&
            pt.y >= window->Pos.y && pt.y <= (window->Pos.y + window->Size.y)) {
            return YES; // Menu captures touch
        }
    }

    if (g->OpenPopupStack.Size > 0) {
        return YES;
    }

    return NO; // Pass touch through to 3D scene
}

@end

// Floating Toggle Button (Draggable FAB)
@interface FloatingESPButton : UIButton
@property (nonatomic, assign) CGPoint lastPoint;
@end

@implementation FloatingESPButton

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.15 alpha:0.85];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.9].CGColor;
        self.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.6].CGColor;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOpacity = 0.8;
        self.layer.shadowOffset = CGSizeZero;
        
        [self setTitle:@"ESP" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor colorWithRed:0.0 green:0.95 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan
{
    CGPoint translation = [pan translationInView:self.superview];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _lastPoint = self.center;
    }
    CGPoint newCenter = CGPointMake(_lastPoint.x + translation.x, _lastPoint.y + translation.y);
    
    // Clamp to screen bounds with margin
    CGRect bounds = self.superview.bounds;
    CGFloat halfW = self.bounds.size.width / 2.0;
    CGFloat halfH = self.bounds.size.height / 2.0;
    newCenter.x = fmax(halfW + 10, fmin(bounds.size.width - halfW - 10, newCenter.x));
    newCenter.y = fmax(halfH + 20, fmin(bounds.size.height - halfH - 20, newCenter.y));
    
    self.center = newCenter;
}

@end

// Main ViewController
@interface SceneViewController () <MTKViewDelegate>
@property (nonatomic, strong) SCNView *scnView;
@property (nonatomic, strong) SCNNode *cameraOrbitNode;
@property (nonatomic, strong) SCNNode *cameraNode;
@property (nonatomic, strong) OverlayTouchView *metalOverlayView;
@property (nonatomic, strong) FloatingESPButton *floatingButton;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, assign) CGPoint lastPanPoint;
@property (nonatomic, assign) CGFloat cameraYaw;
@property (nonatomic, assign) CGFloat cameraPitch;
@property (nonatomic, assign) CGFloat cameraDistance;
@end

@implementation SceneViewController {
    std::vector<DummyTarget> _dummies;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _cameraYaw = 0.0f;
    _cameraPitch = -0.2f;
    _cameraDistance = 14.0f;

    [self setup3DScene];
    [self setupMetalImGui];
    [self setupFloatingButton];
    [self setupCameraGestures];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark - 3D SceneKit Setup

- (void)setup3DScene
{
    _scnView = [[SCNView alloc] initWithFrame:self.view.bounds];
    _scnView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scnView.backgroundColor = [UIColor colorWithRed:0.05 green:0.07 blue:0.10 alpha:1.0];
    _scnView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    _scnView.preferredFramesPerSecond = 60;
    [self.view addSubview:_scnView];

    SCNScene *scene = [SCNScene scene];
    _scnView.scene = scene;

    // Floor with reflective dark grid texture
    SCNFloor *floor = [SCNFloor floor];
    floor.reflectivity = 0.15;
    floor.firstMaterial.diffuse.contents = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];
    SCNNode *floorNode = [SCNNode nodeWithGeometry:floor];
    [scene.rootNode addChildNode:floorNode];

    // Ambient Lighting
    SCNNode *ambientLight = [SCNNode node];
    ambientLight.light = [SCNLight light];
    ambientLight.light.type = SCNLightTypeAmbient;
    ambientLight.light.color = [UIColor colorWithWhite:0.35 alpha:1.0];
    [scene.rootNode addChildNode:ambientLight];

    // Directional Sunlight with Shadows
    SCNNode *sunLight = [SCNNode node];
    sunLight.light = [SCNLight light];
    sunLight.light.type = SCNLightTypeDirectional;
    sunLight.light.color = [UIColor colorWithRed:0.95 green:0.95 blue:1.0 alpha:1.0];
    sunLight.light.castsShadow = YES;
    sunLight.position = SCNVector3Make(15, 25, 15);
    sunLight.eulerAngles = SCNVector3Make(-M_PI / 3.0, M_PI / 4.0, 0);
    [scene.rootNode addChildNode:sunLight];

    // Environment Obstacles / Tactical Crates
    [self addCrateAt:SCNVector3Make(-4.5, 1.2, -3.0) size:SCNVector3Make(2.4, 2.4, 2.4) color:[UIColor colorWithRed:0.25 green:0.35 blue:0.45 alpha:1.0]];
    [self addCrateAt:SCNVector3Make(5.0, 1.5, -4.5) size:SCNVector3Make(2.0, 3.0, 2.0) color:[UIColor colorWithRed:0.20 green:0.30 blue:0.40 alpha:1.0]];
    [self addCrateAt:SCNVector3Make(0.0, 1.0, -8.0) size:SCNVector3Make(4.0, 2.0, 1.5) color:[UIColor colorWithRed:0.30 green:0.25 blue:0.35 alpha:1.0]];

    // Camera Rig (Orbit Node -> Camera Node)
    _cameraOrbitNode = [SCNNode node];
    _cameraOrbitNode.position = SCNVector3Make(0, 1.5, 0);
    [scene.rootNode addChildNode:_cameraOrbitNode];

    _cameraNode = [SCNNode node];
    _cameraNode.camera = [SCNCamera camera];
    _cameraNode.camera.zNear = 0.1;
    _cameraNode.camera.zFar = 100.0;
    _cameraNode.position = SCNVector3Make(0, 0, _cameraDistance);
    [_cameraOrbitNode addChildNode:_cameraNode];

    [self updateCameraTransform];

    // Spawn 4 Humanoid Target Dummies
    [self spawnDummyWithName:"Dummy Alpha [Assault]" position:SCNVector3Make(0, 0, -5.0) patrolX:2.5 health:100.0];
    [self spawnDummyWithName:"Dummy Bravo [Sniper]"  position:SCNVector3Make(-5.0, 0, -9.0) patrolX:0.0 health:85.0];
    [self spawnDummyWithName:"Dummy Charlie [Scout]" position:SCNVector3Make(4.5, 0, -6.5) patrolX:-2.0 health:60.0];
    [self spawnDummyWithName:"Dummy Delta [Patrol]"  position:SCNVector3Make(-2.5, 0, -2.5) patrolX:1.8 health:100.0];
}

- (void)addCrateAt:(SCNVector3)pos size:(SCNVector3)size color:(UIColor *)color
{
    SCNBox *box = [SCNBox boxWithWidth:size.x height:size.y length:size.z chamferRadius:0.08];
    box.firstMaterial.diffuse.contents = color;
    box.firstMaterial.roughness.contents = @(0.6);
    SCNNode *node = [SCNNode nodeWithGeometry:box];
    node.position = pos;
    [_scnView.scene.rootNode addChildNode:node];
}

- (void)spawnDummyWithName:(const char*)name position:(SCNVector3)pos patrolX:(float)patrolOffset health:(float)hp
{
    SCNNode *dummyRoot = [SCNNode node];
    dummyRoot.position = pos;

    // Body Color Materials (Tactical Soldier Appearance)
    SCNMaterial *skinMat = [SCNMaterial material];
    skinMat.diffuse.contents = [UIColor colorWithRed:0.85 green:0.65 blue:0.55 alpha:1.0];

    SCNMaterial *armorMat = [SCNMaterial material];
    armorMat.diffuse.contents = [UIColor colorWithRed:0.20 green:0.28 blue:0.22 alpha:1.0]; // Army Olive

    SCNMaterial *clothMat = [SCNMaterial material];
    clothMat.diffuse.contents = [UIColor colorWithRed:0.18 green:0.20 blue:0.22 alpha:1.0]; // Dark Navy

    // 1. Pelvis / Hips (y = 0.9m)
    SCNBox *pelvisGeo = [SCNBox boxWithWidth:0.34 height:0.22 length:0.22 chamferRadius:0.04];
    pelvisGeo.materials = @[clothMat];
    SCNNode *pelvis = [SCNNode nodeWithGeometry:pelvisGeo];
    pelvis.name = @"pelvis";
    pelvis.position = SCNVector3Make(0, 0.9, 0);
    [dummyRoot addChildNode:pelvis];

    // 2. Spine / Torso (y = 1.25m)
    SCNBox *torsoGeo = [SCNBox boxWithWidth:0.38 height:0.42 length:0.24 chamferRadius:0.05];
    torsoGeo.materials = @[armorMat];
    SCNNode *spine = [SCNNode nodeWithGeometry:torsoGeo];
    spine.name = @"spine";
    spine.position = SCNVector3Make(0, 1.25, 0);
    [dummyRoot addChildNode:spine];

    // 3. Neck (y = 1.55m)
    SCNCylinder *neckGeo = [SCNCylinder cylinderWithRadius:0.08 height:0.12];
    neckGeo.materials = @[skinMat];
    SCNNode *neck = [SCNNode nodeWithGeometry:neckGeo];
    neck.name = @"neck";
    neck.position = SCNVector3Make(0, 1.55, 0);
    [dummyRoot addChildNode:neck];

    // 4. Head (y = 1.78m)
    SCNSphere *headGeo = [SCNSphere sphereWithRadius:0.14];
    headGeo.materials = @[skinMat];
    SCNNode *head = [SCNNode nodeWithGeometry:headGeo];
    head.name = @"head";
    head.position = SCNVector3Make(0, 1.78, 0);
    [dummyRoot addChildNode:head];

    // Tactical Helmet
    SCNSphere *helmetGeo = [SCNSphere sphereWithRadius:0.155];
    helmetGeo.materials = @[armorMat];
    SCNNode *helmet = [SCNNode nodeWithGeometry:helmetGeo];
    helmet.position = SCNVector3Make(0, 0.04, 0);
    [head addChildNode:helmet];

    // 5-7. Left Arm (Shoulder -> Elbow -> Hand)
    SCNNode *lShoulder = [SCNNode node];
    lShoulder.name = @"lShoulder";
    lShoulder.position = SCNVector3Make(-0.28, 1.45, 0);
    [dummyRoot addChildNode:lShoulder];

    SCNCapsule *lUpperArm = [SCNCapsule capsuleWithCapRadius:0.055 height:0.3];
    lUpperArm.materials = @[armorMat];
    SCNNode *lUpperArmNode = [SCNNode nodeWithGeometry:lUpperArm];
    lUpperArmNode.position = SCNVector3Make(-0.06, -0.15, 0);
    [lShoulder addChildNode:lUpperArmNode];

    SCNNode *lElbow = [SCNNode node];
    lElbow.name = @"lElbow";
    lElbow.position = SCNVector3Make(-0.38, 1.15, 0.05);
    [dummyRoot addChildNode:lElbow];

    SCNNode *lHand = [SCNNode node];
    lHand.name = @"lHand";
    lHand.position = SCNVector3Make(-0.42, 0.85, 0.15);
    [dummyRoot addChildNode:lHand];

    // 8-10. Right Arm (Shoulder -> Elbow -> Hand)
    SCNNode *rShoulder = [SCNNode node];
    rShoulder.name = @"rShoulder";
    rShoulder.position = SCNVector3Make(0.28, 1.45, 0);
    [dummyRoot addChildNode:rShoulder];

    SCNCapsule *rUpperArm = [SCNCapsule capsuleWithCapRadius:0.055 height:0.3];
    rUpperArm.materials = @[armorMat];
    SCNNode *rUpperArmNode = [SCNNode nodeWithGeometry:rUpperArm];
    rUpperArmNode.position = SCNVector3Make(0.06, -0.15, 0);
    [rShoulder addChildNode:rUpperArmNode];

    SCNNode *rElbow = [SCNNode node];
    rElbow.name = @"rElbow";
    rElbow.position = SCNVector3Make(0.38, 1.15, -0.05);
    [dummyRoot addChildNode:rElbow];

    SCNNode *rHand = [SCNNode node];
    rHand.name = @"rHand";
    rHand.position = SCNVector3Make(0.42, 0.85, -0.15);
    [dummyRoot addChildNode:rHand];

    // 11-13. Left Leg (Hip -> Knee -> Foot)
    SCNNode *lHip = [SCNNode node];
    lHip.name = @"lHip";
    lHip.position = SCNVector3Make(-0.16, 0.82, 0);
    [dummyRoot addChildNode:lHip];

    SCNCapsule *lLegGeo = [SCNCapsule capsuleWithCapRadius:0.065 height:0.4];
    lLegGeo.materials = @[clothMat];
    SCNNode *lThigh = [SCNNode nodeWithGeometry:lLegGeo];
    lThigh.position = SCNVector3Make(0, -0.2, 0);
    [lHip addChildNode:lThigh];

    SCNNode *lKnee = [SCNNode node];
    lKnee.name = @"lKnee";
    lKnee.position = SCNVector3Make(-0.17, 0.45, 0.04);
    [dummyRoot addChildNode:lKnee];

    SCNNode *lFoot = [SCNNode node];
    lFoot.name = @"lFoot";
    lFoot.position = SCNVector3Make(-0.18, 0.08, 0.1);
    [dummyRoot addChildNode:lFoot];

    // 14-16. Right Leg (Hip -> Knee -> Foot)
    SCNNode *rHip = [SCNNode node];
    rHip.name = @"rHip";
    rHip.position = SCNVector3Make(0.16, 0.82, 0);
    [dummyRoot addChildNode:rHip];

    SCNNode *rThigh = [SCNNode nodeWithGeometry:lLegGeo];
    rThigh.position = SCNVector3Make(0, -0.2, 0);
    [rHip addChildNode:rThigh];

    SCNNode *rKnee = [SCNNode node];
    rKnee.name = @"rKnee";
    rKnee.position = SCNVector3Make(0.17, 0.45, -0.04);
    [dummyRoot addChildNode:rKnee];

    SCNNode *rFoot = [SCNNode node];
    rFoot.name = @"rFoot";
    rFoot.position = SCNVector3Make(0.18, 0.08, -0.1);
    [dummyRoot addChildNode:rFoot];

    [_scnView.scene.rootNode addChildNode:dummyRoot];

    // Animate Dummy Patrol / Movement
    if (std::fabs(patrolOffset) > 0.1f) {
        SCNAction *moveRight = [SCNAction moveByX:patrolOffset y:0 z:0 duration:3.0];
        moveRight.timingMode = SCNActionTimingModeEaseInEaseOut;
        SCNAction *wait = [SCNAction waitForDuration:0.5];
        SCNAction *moveLeft = [SCNAction moveByX:-patrolOffset y:0 z:0 duration:3.0];
        moveLeft.timingMode = SCNActionTimingModeEaseInEaseOut;
        SCNAction *sequence = [SCNAction sequence:@[moveRight, wait, moveLeft, wait]];
        [dummyRoot runAction:[SCNAction repeatActionForever:sequence]];
    }

    DummyTarget target;
    target.name = name;
    target.rootNode = dummyRoot;
    target.health = hp;
    target.maxHealth = 100.0f;
    _dummies.push_back(target);
}

#pragma mark - Metal & Dear ImGui Setup

- (void)setupMetalImGui
{
    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];

    _metalOverlayView = [[OverlayTouchView alloc] initWithFrame:self.view.bounds];
    _metalOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _metalOverlayView.device = _device;
    _metalOverlayView.delegate = self;
    _metalOverlayView.clearColor = MTLClearColorMake(0, 0, 0, 0);
    _metalOverlayView.backgroundColor = [UIColor clearColor];
    _metalOverlayView.clipsToBounds = YES;
    [self.view addSubview:_metalOverlayView];

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    (void)io;

    // Apply sleek Dark Modern styling
    ImGui::StyleColorsDark();
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowRounding = 10.0f;
    style.FrameRounding = 6.0f;
    style.PopupRounding = 8.0f;
    style.ScrollbarRounding = 9.0f;
    style.GrabRounding = 6.0f;
    style.TabRounding = 6.0f;
    style.WindowBorderSize = 1.0f;
    style.FrameBorderSize = 0.5f;
    style.Colors[ImGuiCol_WindowBg] = ImVec4(0.08f, 0.10f, 0.14f, 0.90f);
    style.Colors[ImGuiCol_Border] = ImVec4(0.0f, 0.8f, 1.0f, 0.45f);
    style.Colors[ImGuiCol_Header] = ImVec4(0.12f, 0.35f, 0.55f, 0.80f);
    style.Colors[ImGuiCol_Button] = ImVec4(0.15f, 0.38f, 0.60f, 0.85f);
    style.Colors[ImGuiCol_ButtonHovered] = ImVec4(0.20f, 0.50f, 0.78f, 1.0f);
    style.Colors[ImGuiCol_CheckMark] = ImVec4(0.0f, 0.95f, 1.0f, 1.0f);
    style.Colors[ImGuiCol_SliderGrab] = ImVec4(0.0f, 0.85f, 1.0f, 1.0f);

    ImGui_ImplMetal_Init(_device);
}

- (void)setupFloatingButton
{
    CGFloat btnSize = 56.0f;
    CGRect frame = CGRectMake(self.view.bounds.size.width - btnSize - 16.0f, 48.0f, btnSize, btnSize);
    _floatingButton = [[FloatingESPButton alloc] initWithFrame:frame];
    _floatingButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [_floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_floatingButton];
}

- (void)setupCameraGestures
{
    // Double tap with 2 fingers to toggle menu
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 2;
    [self.view addGestureRecognizer:doubleTap];

    // Pan to orbit camera
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCameraPan:)];
    [self.view addGestureRecognizer:pan];

    // Pinch to zoom camera
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleCameraPinch:)];
    [self.view addGestureRecognizer:pinch];
}

- (void)toggleMenu
{
    g_ShowMenu = !g_ShowMenu;
}

- (void)handleCameraPan:(UIPanGestureRecognizer *)pan
{
    if (pan.state == UIGestureRecognizerStateBegan) {
        _lastPanPoint = [pan locationInView:self.view];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint currentPoint = [pan locationInView:self.view];
        CGFloat dx = currentPoint.x - _lastPanPoint.x;
        CGFloat dy = currentPoint.y - _lastPanPoint.y;
        _lastPanPoint = currentPoint;

        _cameraYaw -= dx * 0.008f;
        _cameraPitch = fmaxf(-1.2f, fminf(0.5f, _cameraPitch - dy * 0.008f));
        [self updateCameraTransform];
    }
}

- (void)handleCameraPinch:(UIPinchGestureRecognizer *)pinch
{
    if (pinch.state == UIGestureRecognizerStateChanged) {
        CGFloat scale = pinch.scale;
        pinch.scale = 1.0;
        _cameraDistance = fmaxf(4.0f, fminf(30.0f, _cameraDistance / scale));
        [self updateCameraTransform];
    }
}

- (void)updateCameraTransform
{
    _cameraOrbitNode.eulerAngles = SCNVector3Make(_cameraPitch, _cameraYaw, 0);
    _cameraNode.position = SCNVector3Make(0, 0, _cameraDistance);
}

#pragma mark - Touch Event Forwarding for ImGui

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    UITouch *anyTouch = event.allTouches.anyObject;
    CGPoint touchLocation = [anyTouch locationInView:self.view];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(touchLocation.x, touchLocation.y);

    BOOL hasActiveTouch = NO;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            hasActiveTouch = YES;
            break;
        }
    }
    io.MouseDown[0] = hasActiveTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateIOWithTouchEvent:event]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateIOWithTouchEvent:event]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateIOWithTouchEvent:event]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateIOWithTouchEvent:event]; }

#pragma mark - Color Picker Helper

static void RenderColorButton(const char *name, ImVec4 &color)
{
    ImGui::PushID(name);
    if (ImGui::ColorButton("##btn", color, ImGuiColorEditFlags_NoPicker | ImGuiColorEditFlags_AlphaPreviewHalf, ImVec2(40, 24))) {
        ImGui::OpenPopup("ColorPopup");
    }
    if (ImGui::BeginPopup("ColorPopup")) {
        ImGui::Text("Select Color: %s", name);
        ImGui::Separator();
        ImGui::ColorPicker4("##picker", (float*)&color, ImGuiColorEditFlags_NoSidePreview | ImGuiColorEditFlags_NoSmallPreview);
        ImGui::EndPopup();
    }
    ImGui::PopID();
}

#pragma mark - World To Screen Projector

- (BOOL)projectWorldPos:(SCNVector3)worldPos toScreen:(ImVec2 &)outScreen distance:(float *)outDist
{
    SCNVector3 projected = [_scnView projectPoint:worldPos];

    // projected.z is normalized depth (0.0 = near plane, 1.0 = far plane)
    if (projected.z <= 0.0f || projected.z >= 1.0f) {
        return NO; // Behind camera
    }

    outScreen = ImVec2(projected.x, projected.y);

    if (outDist) {
        SCNVector3 camWorld = [_scnView.pointOfView.presentationNode convertPosition:SCNVector3Zero toNode:nil];
        float dx = worldPos.x - camWorld.x;
        float dy = worldPos.y - camWorld.y;
        float dz = worldPos.z - camWorld.z;
        *outDist = sqrtf(dx * dx + dy * dy + dz * dz);
    }
    return YES;
}

#pragma mark - MTKView Delegate (Drawing Frame)

- (void)drawInMTKView:(MTKView *)view
{
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize.x = view.bounds.size.width;
    io.DisplaySize.y = view.bounds.size.height;
    CGFloat scale = view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
    io.DisplayFramebufferScale = ImVec2(scale, scale);
    io.DeltaTime = 1.0f / float(view.preferredFramesPerSecond ?: 60);

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPass = view.currentRenderPassDescriptor;
    if (!renderPass) return;

    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];

    ImGui_ImplMetal_NewFrame(renderPass);
    ImGui::NewFrame();

    // 1. Draw ESP Visuals (Bone Skeleton, Boxes, Lines, Distance)
    if (g_Settings.bMasterESP) {
        [self drawESPOverlays];
    }

    // 2. Draw Center Aim FOV Circle
    if (g_Settings.bFOVCircle) {
        ImDrawList *drawList = ImGui::GetBackgroundDrawList();
        ImVec2 center(io.DisplaySize.x / 2.0f, io.DisplaySize.y / 2.0f);
        drawList->AddCircle(center, g_Settings.fovRadius, ImColor(g_Settings.fovColor), 48, 1.5f);
        drawList->AddCircle(center, 2.5f, ImColor(0.0f, 0.95f, 1.0f, 1.0f), 12, 2.0f); // Center crosshair dot
    }

    // 3. Render Modern Floating Debug Menu
    if (g_ShowMenu) {
        [self renderDebugMenu];
    }

    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, renderEncoder);

    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}

#pragma mark - ESP Visual Rendering Engine

- (void)drawESPOverlays
{
    ImDrawList *drawList = ImGui::GetBackgroundDrawList();
    ImGuiIO &io = ImGui::GetIO();
    float screenMidX = io.DisplaySize.x / 2.0f;
    float screenBottomY = io.DisplaySize.y;

    for (const auto &dummy : _dummies) {
        SCNNode *rootNode = dummy.rootNode.presentationNode;
        SCNVector3 rootWorld = [rootNode convertPosition:SCNVector3Zero toNode:nil];

        // Project feet and head
        ImVec2 feetScr, headScr;
        float distance = 0.0f;
        if (![self projectWorldPos:rootWorld toScreen:feetScr distance:&distance]) continue;
        if (![self projectWorldPos:SCNVector3Make(rootWorld.x, rootWorld.y + g_Settings.headOffset, rootWorld.z) toScreen:headScr distance:nil]) continue;

        float topY = fminf(feetScr.y, headScr.y);
        float botY = fmaxf(feetScr.y, headScr.y);
        float height = botY - topY;
        if (height < 4.0f) continue;

        float width = height * g_Settings.boxWidthScale;
        float halfW = width / 2.0f;
        float centerX = (feetScr.x + headScr.x) / 2.0f;

        ImVec2 boxMin(centerX - halfW, topY);
        ImVec2 boxMax(centerX + halfW, botY);

        // 1. 2D Bounding Box
        if (g_Settings.bBox) {
            drawList->AddRect(boxMin, boxMax, ImColor(0, 0, 0, 220), 0.0f, 0, 3.0f);
            drawList->AddRect(boxMin, boxMax, ImColor(g_Settings.boxColor), 0.0f, 0, 1.5f);
        }

        // 2. Snaplines (from bottom center of screen to dummy feet)
        if (g_Settings.bSnaplines) {
            drawList->AddLine(ImVec2(screenMidX, screenBottomY), ImVec2(centerX, botY), ImColor(g_Settings.lineColor), 1.5f);
        }

        // 3. 15-Joint Humanoid Bone Skeleton ESP
        if (g_Settings.bSkeleton) {
            // Helper lambda to fetch world position of a named bone node
            auto GetBoneWorld = [&](NSString *boneName) -> SCNVector3 {
                SCNNode *bNode = [rootNode childNodeWithName:boneName recursively:YES];
                if (bNode) {
                    return [bNode convertPosition:SCNVector3Zero toNode:nil];
                }
                return rootWorld;
            };

            auto DrawBoneLine = [&](NSString *b1, NSString *b2) {
                ImVec2 s1, s2;
                if ([self projectWorldPos:GetBoneWorld(b1) toScreen:s1 distance:nil] &&
                    [self projectWorldPos:GetBoneWorld(b2) toScreen:s2 distance:nil]) {
                    drawList->AddLine(s1, s2, ImColor(0, 0, 0, 220), 3.0f);
                    drawList->AddLine(s1, s2, ImColor(g_Settings.skeletonColor), 1.8f);
                }
            };

            // Head Circle
            ImVec2 headCenter;
            if ([self projectWorldPos:GetBoneWorld(@"head") toScreen:headCenter distance:nil]) {
                float headRadius = fmaxf(4.0f, height * 0.07f);
                drawList->AddCircle(headCenter, headRadius, ImColor(0, 0, 0, 220), 16, 3.0f);
                drawList->AddCircle(headCenter, headRadius, ImColor(g_Settings.skeletonColor), 16, 1.8f);
            }

            // Torso & Spine
            DrawBoneLine(@"head", @"neck");
            DrawBoneLine(@"neck", @"spine");
            DrawBoneLine(@"spine", @"pelvis");

            // Arms
            DrawBoneLine(@"neck", @"lShoulder");
            DrawBoneLine(@"lShoulder", @"lElbow");
            DrawBoneLine(@"lElbow", @"lHand");

            DrawBoneLine(@"neck", @"rShoulder");
            DrawBoneLine(@"rShoulder", @"rElbow");
            DrawBoneLine(@"rElbow", @"rHand");

            // Legs
            DrawBoneLine(@"pelvis", @"lHip");
            DrawBoneLine(@"lHip", @"lKnee");
            DrawBoneLine(@"lKnee", @"lFoot");

            DrawBoneLine(@"pelvis", @"rHip");
            DrawBoneLine(@"rHip", @"rKnee");
            DrawBoneLine(@"rKnee", @"rFoot");
        }

        // 4. Health Bar (Vertical bar on left of box)
        if (g_Settings.bHealth) {
            float barW = 3.5f;
            float barMargin = 4.0f;
            ImVec2 bgMin(boxMin.x - barMargin - barW, boxMin.y);
            ImVec2 bgMax(boxMin.x - barMargin, boxMax.y);
            drawList->AddRectFilled(bgMin, bgMax, ImColor(0, 0, 0, 180));

            float hpRatio = fmaxf(0.0f, fminf(1.0f, dummy.health / dummy.maxHealth));
            float barFillHeight = height * hpRatio;
            ImVec2 fillMin(bgMin.x, bgMax.y - barFillHeight);
            ImVec4 hpColor = hpRatio > 0.5f ? ImVec4(0.0f, 1.0f, 0.3f, 1.0f) : ImVec4(1.0f, 0.2f, 0.0f, 1.0f);
            drawList->AddRectFilled(fillMin, bgMax, ImColor(hpColor));
        }

        // 5. Distance and Target Info Label
        if (g_Settings.bDistance) {
            char label[64];
            snprintf(label, sizeof(label), "%s [%.0fm]", dummy.name.c_str(), distance);
            ImVec2 textSize = ImGui::CalcTextSize(label);
            ImVec2 textPos(centerX - (textSize.x / 2.0f), botY + 3.0f);

            drawList->AddText(ImVec2(textPos.x + 1, textPos.y + 1), ImColor(0, 0, 0, 220), label);
            drawList->AddText(textPos, ImColor(255, 255, 255, 255), label);
        }
    }
}

#pragma mark - Modern Debug ImGui Menu

- (void)renderDebugMenu
{
    CGFloat screenW = self.view.bounds.size.width;
    CGFloat screenH = self.view.bounds.size.height;
    CGFloat menuW = fminf(380.0f, screenW - 30.0f);
    CGFloat menuH = fminf(320.0f, screenH - 60.0f);

    ImGui::SetNextWindowSize(ImVec2(menuW, menuH), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowPos(ImVec2((screenW - menuW) / 2.0f, 50.0f), ImGuiCond_FirstUseEver);

    if (ImGui::Begin("ESP 3D Studio Telemetry", &g_ShowMenu, ImGuiWindowFlags_NoCollapse)) {
        if (ImGui::BeginTabBar("MainTabs")) {
            
            // TAB 1: ESP Visuals
            if (ImGui::BeginTabItem("ESP Settings")) {
                ImGui::Spacing();
                ImGui::Checkbox("Master ESP", &g_Settings.bMasterESP);
                ImGui::Separator();

                ImGui::Checkbox("15-Joint Skeleton ESP", &g_Settings.bSkeleton);
                ImGui::SameLine(220);
                RenderColorButton("Skeleton", g_Settings.skeletonColor);

                ImGui::Checkbox("2D Bounding Box", &g_Settings.bBox);
                ImGui::SameLine(220);
                RenderColorButton("Box", g_Settings.boxColor);

                ImGui::Checkbox("Snaplines", &g_Settings.bSnaplines);
                ImGui::SameLine(220);
                RenderColorButton("Line", g_Settings.lineColor);

                ImGui::Checkbox("Distance & Target Tags", &g_Settings.bDistance);
                ImGui::Checkbox("Health Bars", &g_Settings.bHealth);

                ImGui::Separator();
                ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "Box Calibration");
                ImGui::SliderFloat("Head Offset", &g_Settings.headOffset, 1.0f, 2.5f, "%.2f m");
                ImGui::SliderFloat("Width Scale", &g_Settings.boxWidthScale, 0.2f, 0.8f, "%.2f");

                ImGui::EndTabItem();
            }

            // TAB 2: Aim Assist & FOV
            if (ImGui::BeginTabItem("Aim & FOV")) {
                ImGui::Spacing();
                ImGui::Checkbox("Draw FOV Circle", &g_Settings.bFOVCircle);
                ImGui::SameLine(220);
                RenderColorButton("FOV", g_Settings.fovColor);

                ImGui::SliderFloat("FOV Radius", &g_Settings.fovRadius, 30.0f, 350.0f, "%.0f px");

                ImGui::Separator();
                ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "Aim Assist Telemetry");
                ImGui::Text("Target Bone: Head (Joint 4)");
                ImGui::Text("Aim Smoothing: 0.15 (Dynamic)");
                ImGui::Text("Gesture: Swipe 1 finger to orbit 3D camera");
                ImGui::Text("Zoom: Pinch with 2 fingers to zoom");

                ImGui::EndTabItem();
            }

            // TAB 3: Telemetry & Inspector
            if (ImGui::BeginTabItem("Entities & Diagnostics")) {
                ImGui::Spacing();
                ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.4f, 1.0f), "Live Targets in Scene: %zu", _dummies.size());
                ImGui::Separator();

                for (size_t i = 0; i < _dummies.size(); i++) {
                    const auto &d = _dummies[i];
                    SCNVector3 pos = [d.rootNode.presentationNode convertPosition:SCNVector3Zero toNode:nil];
                    ImGui::Text("[%zu] %s: (%.1f, %.1f, %.1f) - %.0f HP", i + 1, d.name.c_str(), pos.x, pos.y, pos.z, d.health);
                }

                ImGui::Separator();
                ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "Engine Telemetry");
                ImGui::Text("Framerate: %.1f FPS", ImGui::GetIO().Framerate);
                ImGui::Text("Screen Size: %.0f x %.0f", ImGui::GetIO().DisplaySize.x, ImGui::GetIO().DisplaySize.y);
                ImGui::Text("Camera Distance: %.1fm", _cameraDistance);

                ImGui::EndTabItem();
            }

            // TAB 4: Instructions
            if (ImGui::BeginTabItem("Controls")) {
                ImGui::Spacing();
                ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "Mobile Gesture Shortcuts:");
                ImGui::BulletText("Tap 'ESP' Floating Badge to open/close menu");
                ImGui::BulletText("Drag 'ESP' Badge to move it anywhere");
                ImGui::BulletText("Double-tap with 2 fingers to toggle menu");
                ImGui::BulletText("Drag 1 finger anywhere to orbit 3D camera");
                ImGui::BulletText("Pinch 2 fingers to zoom camera in/out");

                ImGui::Spacing();
                if (ImGui::Button("Close Menu", ImVec2(120, 32))) {
                    g_ShowMenu = false;
                }

                ImGui::EndTabItem();
            }

            ImGui::EndTabBar();
        }
    }
    ImGui::End();
}

@end

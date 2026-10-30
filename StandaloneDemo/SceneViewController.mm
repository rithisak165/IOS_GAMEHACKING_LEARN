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

// =========================================================================================
// OXSAK STATE & TELEMETRY CONFIGURATION (Orange Cyberpunk Theme)
// =========================================================================================
struct OXSAKState {
    int currentTab    = 0;    // 0: AIMBOT, 1: ESP, 2: MISC, 3: SETTINGS
    int currentSubTab = 0;    // 0: Aimbot, 1: Silent Aim

    // AIMBOT & SILENT AIM Settings (Matching Reference Reference)
    bool  bEnableAim          = false;
    bool  bVisibleOnly        = true;
    bool  bIgnoreTeam         = true;
    bool  bSticky             = true;
    bool  bAutoShoot          = false;
    bool  bLockLine           = true;
    float fovRadius           = 70.0f;
    float smoothness          = 10.0f;
    float maxTurn             = 0.0f;
    float reactionMs          = 0.0f;
    float jitter              = 0.07f;

    // ESP Visuals Settings
    bool  bEnableESP          = true;
    bool  bSkeleton           = true;
    bool  bBox                = true;
    bool  bSnaplines          = true;
    bool  bDistance           = true;
    bool  bHealth             = true;
    float headOffset          = 1.85f;
    float botOffset           = 0.00f;
    float boxWidthScale       = 0.45f;

    // Custom Color Palette (#FF8A00 / #FFB347)
    ImVec4 colPrimaryOrange   = ImVec4(1.0f, 0.54f, 0.0f, 1.0f);   // #FF8A00
    ImVec4 colSecondaryOrange = ImVec4(1.0f, 0.70f, 0.28f, 1.0f);  // #FFB347
    ImVec4 colSkeleton        = ImVec4(1.0f, 0.54f, 0.0f, 0.95f);  // Orange Skeleton
    ImVec4 colBox             = ImVec4(1.0f, 0.35f, 0.1f, 1.0f);   // Warm Box
    ImVec4 colSnapline        = ImVec4(1.0f, 0.70f, 0.28f, 0.9f);  // Tracer Line
    ImVec4 colFOV             = ImVec4(1.0f, 0.54f, 0.0f, 0.45f);  // FOV Circle
};

static OXSAKState g_State;
static bool g_ShowMenu = true;

// Structure for 3D Humanoid Dummies
struct DummyTarget {
    std::string name;
    SCNNode *rootNode;
    float health;
    float maxHealth;
};

// =========================================================================================
// TOUCH PASSTHROUGH OVERLAY VIEW
// =========================================================================================
@interface OverlayTouchView : MTKView
@end

@implementation OverlayTouchView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!g_ShowMenu || !ImGui::GetCurrentContext()) {
        return NO; // Menu closed -> touches pass to 3D orbit camera
    }

    ImGuiContext *g = ImGui::GetCurrentContext();
    ImVec2 pt = ImVec2(point.x, point.y);

    for (int i = 0; i < g->Windows.Size; i++) {
        ImGuiWindow *window = g->Windows[i];
        if (!window || !window->WasActive || window->Hidden) continue;
        if (window->Flags & ImGuiWindowFlags_NoInputs) continue;

        if (pt.x >= window->Pos.x && pt.x <= (window->Pos.x + window->Size.x) &&
            pt.y >= window->Pos.y && pt.y <= (window->Pos.y + window->Size.y)) {
            return YES; // Menu captures touch
        }
    }

    if (g->OpenPopupStack.Size > 0) return YES;
    return NO;
}

@end

// =========================================================================================
// FLOATING OXSAK LAUNCHER BADGE (Supplied Exact Logo with Glowing Orange Shadow)
// =========================================================================================
@interface FloatingOXSAKButton : UIView
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIImageView *logoImageView;
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, copy) void (^onTap)(void);
@end

@implementation FloatingOXSAKButton

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.masksToBounds = NO;

        // Glowing outer orange shadow (#FF8A00)
        self.layer.shadowColor = [UIColor colorWithRed:1.0 green:0.54 blue:0.0 alpha:0.95].CGColor;
        self.layer.shadowRadius = 14.0;
        self.layer.shadowOpacity = 0.90;
        self.layer.shadowOffset = CGSizeMake(0, 0);

        // Inner circular image view displaying the exact OXSAK logo
        _logoImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _logoImageView.contentMode = UIViewContentModeScaleAspectFit;
        _logoImageView.layer.cornerRadius = frame.size.width / 2.0;
        _logoImageView.layer.masksToBounds = YES;
        _logoImageView.layer.borderWidth = 2.5;
        _logoImageView.layer.borderColor = [UIColor colorWithRed:1.0 green:0.54 blue:0.0 alpha:0.95].CGColor;
        _logoImageView.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.95];

        NSString *path = [[NSBundle mainBundle] pathForResource:@"oxsak_badge" ofType:@"png"];
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        if (!img) img = [UIImage imageNamed:@"oxsak_badge.png"];
        if (img) {
            _logoImageView.image = img;
        }
        [self addSubview:_logoImageView];

        // Invisible touch button over the badge
        _actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _actionButton.frame = self.bounds;
        [_actionButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_actionButton];

        // Restore persisted coordinates
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        if ([defs objectForKey:@"OXSAK_Btn_X"] && [defs objectForKey:@"OXSAK_Btn_Y"]) {
            CGFloat x = [defs floatForKey:@"OXSAK_Btn_X"];
            CGFloat y = [defs floatForKey:@"OXSAK_Btn_Y"];
            self.center = CGPointMake(x, y);
        }

        // Draggable gesture
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)buttonTapped
{
    if (self.onTap) self.onTap();
}

- (void)handlePan:(UIPanGestureRecognizer *)pan
{
    CGPoint translation = [pan translationInView:self.superview];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _lastPoint = self.center;
    }
    CGPoint newCenter = CGPointMake(_lastPoint.x + translation.x, _lastPoint.y + translation.y);
    CGRect bounds = self.superview.bounds;
    CGFloat halfW = self.bounds.size.width / 2.0;
    CGFloat halfH = self.bounds.size.height / 2.0;
    newCenter.x = fmax(halfW + 12, fmin(bounds.size.width - halfW - 12, newCenter.x));
    newCenter.y = fmax(halfH + 20, fmin(bounds.size.height - halfH - 20, newCenter.y));
    self.center = newCenter;

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        [defs setFloat:self.center.x forKey:@"OXSAK_Btn_X"];
        [defs setFloat:self.center.y forKey:@"OXSAK_Btn_Y"];
        [defs synchronize];
    }
}

@end

// =========================================================================================
// MAIN VIEW CONTROLLER (3D SceneKit + Metal ImGui)
// =========================================================================================
@interface SceneViewController () <MTKViewDelegate>
@property (nonatomic, strong) SCNView *scnView;
@property (nonatomic, strong) SCNNode *cameraOrbitNode;
@property (nonatomic, strong) SCNNode *cameraNode;
@property (nonatomic, strong) OverlayTouchView *metalOverlayView;
@property (nonatomic, strong) FloatingOXSAKButton *floatingButton;
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
    _scnView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:1.0];
    _scnView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    _scnView.preferredFramesPerSecond = 60;
    [self.view addSubview:_scnView];

    SCNScene *scene = [SCNScene scene];
    _scnView.scene = scene;

    // Dark grid floor with reflective surface
    SCNFloor *floor = [SCNFloor floor];
    floor.reflectivity = 0.18;
    floor.firstMaterial.diffuse.contents = [UIColor colorWithRed:0.08 green:0.08 blue:0.11 alpha:1.0];
    SCNNode *floorNode = [SCNNode nodeWithGeometry:floor];
    [scene.rootNode addChildNode:floorNode];

    // Ambient Light
    SCNNode *ambientLight = [SCNNode node];
    ambientLight.light = [SCNLight light];
    ambientLight.light.type = SCNLightTypeAmbient;
    ambientLight.light.color = [UIColor colorWithWhite:0.32 alpha:1.0];
    [scene.rootNode addChildNode:ambientLight];

    // Directional Sunlight with Shadows
    SCNNode *sunLight = [SCNNode node];
    sunLight.light = [SCNLight light];
    sunLight.light.type = SCNLightTypeDirectional;
    sunLight.light.color = [UIColor colorWithRed:1.0 green:0.95 blue:0.90 alpha:1.0];
    sunLight.light.castsShadow = YES;
    sunLight.position = SCNVector3Make(15, 25, 15);
    sunLight.eulerAngles = SCNVector3Make(-M_PI / 3.0, M_PI / 4.0, 0);
    [scene.rootNode addChildNode:sunLight];

    // Tactical Crates / Cover
    [self addCrateAt:SCNVector3Make(-4.5, 1.2, -3.0) size:SCNVector3Make(2.4, 2.4, 2.4) color:[UIColor colorWithRed:0.20 green:0.20 blue:0.28 alpha:1.0]];
    [self addCrateAt:SCNVector3Make(5.0, 1.5, -4.5) size:SCNVector3Make(2.0, 3.0, 2.0) color:[UIColor colorWithRed:0.18 green:0.22 blue:0.28 alpha:1.0]];
    [self addCrateAt:SCNVector3Make(0.0, 1.0, -8.0) size:SCNVector3Make(4.0, 2.0, 1.5) color:[UIColor colorWithRed:0.25 green:0.20 blue:0.25 alpha:1.0]];

    // Camera Rig
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
    SCNNode *node = [SCNNode nodeWithGeometry:box];
    node.position = pos;
    [_scnView.scene.rootNode addChildNode:node];
}

- (void)spawnDummyWithName:(const char*)name position:(SCNVector3)pos patrolX:(float)patrolOffset health:(float)hp
{
    SCNNode *dummyRoot = [SCNNode node];
    dummyRoot.position = pos;

    SCNMaterial *skinMat = [SCNMaterial material];
    skinMat.diffuse.contents = [UIColor colorWithRed:0.85 green:0.65 blue:0.55 alpha:1.0];

    SCNMaterial *armorMat = [SCNMaterial material];
    armorMat.diffuse.contents = [UIColor colorWithRed:0.18 green:0.22 blue:0.20 alpha:1.0];

    SCNMaterial *clothMat = [SCNMaterial material];
    clothMat.diffuse.contents = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];

    // 1. Pelvis (y = 0.9m)
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

    // Arms
    SCNNode *lShoulder = [SCNNode node]; lShoulder.name = @"lShoulder"; lShoulder.position = SCNVector3Make(-0.28, 1.45, 0); [dummyRoot addChildNode:lShoulder];
    SCNNode *lElbow    = [SCNNode node]; lElbow.name    = @"lElbow";    lElbow.position    = SCNVector3Make(-0.38, 1.15, 0.05); [dummyRoot addChildNode:lElbow];
    SCNNode *lHand     = [SCNNode node]; lHand.name     = @"lHand";     lHand.position     = SCNVector3Make(-0.42, 0.85, 0.15); [dummyRoot addChildNode:lHand];

    SCNNode *rShoulder = [SCNNode node]; rShoulder.name = @"rShoulder"; rShoulder.position = SCNVector3Make(0.28, 1.45, 0); [dummyRoot addChildNode:rShoulder];
    SCNNode *rElbow    = [SCNNode node]; rElbow.name    = @"rElbow";    rElbow.position    = SCNVector3Make(0.38, 1.15, -0.05); [dummyRoot addChildNode:rElbow];
    SCNNode *rHand     = [SCNNode node]; rHand.name     = @"rHand";     rHand.position     = SCNVector3Make(0.42, 0.85, -0.15); [dummyRoot addChildNode:rHand];

    // Legs
    SCNNode *lHip  = [SCNNode node]; lHip.name  = @"lHip";  lHip.position  = SCNVector3Make(-0.16, 0.82, 0); [dummyRoot addChildNode:lHip];
    SCNNode *lKnee = [SCNNode node]; lKnee.name = @"lKnee"; lKnee.position = SCNVector3Make(-0.17, 0.45, 0.04); [dummyRoot addChildNode:lKnee];
    SCNNode *lFoot = [SCNNode node]; lFoot.name = @"lFoot"; lFoot.position = SCNVector3Make(-0.18, 0.08, 0.1); [dummyRoot addChildNode:lFoot];

    SCNNode *rHip  = [SCNNode node]; rHip.name  = @"rHip";  rHip.position  = SCNVector3Make(0.16, 0.82, 0); [dummyRoot addChildNode:rHip];
    SCNNode *rKnee = [SCNNode node]; rKnee.name = @"rKnee"; rKnee.position = SCNVector3Make(0.17, 0.45, -0.04); [dummyRoot addChildNode:rKnee];
    SCNNode *rFoot = [SCNNode node]; rFoot.name = @"rFoot"; rFoot.position = SCNVector3Make(0.18, 0.08, -0.1); [dummyRoot addChildNode:rFoot];

    [_scnView.scene.rootNode addChildNode:dummyRoot];

    // Patrol Animation
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

    // Load authentic Roboto Condensed Font
    NSString *fontPath = [[NSBundle mainBundle] pathForResource:@"RobotoCondensed-Bold" ofType:@"ttf"];
    if (!fontPath || ![[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        fontPath = [[NSBundle mainBundle] pathForResource:@"RobotoCondensed-Regular" ofType:@"ttf"];
    }
    if (fontPath && [[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        io.Fonts->AddFontFromFileTTF(fontPath.UTF8String, 18.0f, NULL, io.Fonts->GetGlyphRangesDefault());
    } else {
        io.Fonts->AddFontDefault();
    }

    // Apply exact OXSAK Orange Cyberpunk Theme (#101014, #15151B, #20202B, #FF8A00)
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowRounding    = 12.0f;
    style.FrameRounding     = 8.0f;
    style.PopupRounding     = 8.0f;
    style.ScrollbarRounding = 9.0f;
    style.GrabRounding      = 8.0f;
    style.ChildRounding     = 10.0f;
    style.WindowBorderSize  = 1.2f;
    style.FrameBorderSize   = 0.0f;

    style.Colors[ImGuiCol_WindowBg]         = ImVec4(0.063f, 0.063f, 0.078f, 0.96f); // #101014
    style.Colors[ImGuiCol_Border]           = ImVec4(1.0f, 0.54f, 0.0f, 0.50f);      // #FF8A00 Border
    style.Colors[ImGuiCol_FrameBg]          = ImVec4(0.125f, 0.125f, 0.168f, 1.00f); // #20202B
    style.Colors[ImGuiCol_FrameBgHovered]   = ImVec4(0.18f, 0.18f, 0.24f, 1.00f);
    style.Colors[ImGuiCol_FrameBgActive]    = ImVec4(0.22f, 0.22f, 0.30f, 1.00f);
    style.Colors[ImGuiCol_Button]           = ImVec4(0.125f, 0.125f, 0.168f, 0.90f);
    style.Colors[ImGuiCol_ButtonHovered]    = ImVec4(1.0f, 0.54f, 0.0f, 0.40f);
    style.Colors[ImGuiCol_ButtonActive]     = ImVec4(1.0f, 0.54f, 0.0f, 0.85f);
    style.Colors[ImGuiCol_CheckMark]        = ImVec4(1.0f, 0.54f, 0.0f, 1.00f);
    style.Colors[ImGuiCol_SliderGrab]       = ImVec4(1.0f, 0.54f, 0.0f, 1.00f);
    style.Colors[ImGuiCol_SliderGrabActive] = ImVec4(1.0f, 0.70f, 0.28f, 1.00f);
    style.Colors[ImGuiCol_ScrollbarBg]      = ImVec4(0.08f, 0.08f, 0.10f, 0.60f);
    style.Colors[ImGuiCol_ScrollbarGrab]    = ImVec4(1.0f, 0.54f, 0.0f, 0.65f);
    style.Colors[ImGuiCol_Text]             = ImVec4(1.0f, 1.0f, 1.0f, 1.00f);

    ImGui_ImplMetal_Init(_device);
}

- (void)setupFloatingButton
{
    CGFloat btnSize = 58.0f;
    CGRect frame = CGRectMake(self.view.bounds.size.width - btnSize - 16.0f, 44.0f, btnSize, btnSize);
    _floatingButton = [[FloatingOXSAKButton alloc] initWithFrame:frame];
    _floatingButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    __weak SceneViewController *weakSelf = self;
    _floatingButton.onTap = ^{
        [weakSelf toggleMenu];
    };
    [self.view addSubview:_floatingButton];
}

- (void)setupCameraGestures
{
    // Double-tap with 2 fingers to toggle menu
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 2;
    [self.view addGestureRecognizer:doubleTap];

    // Pan to orbit 3D camera
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCameraPan:)];
    [self.view addGestureRecognizer:pan];

    // Pinch to zoom 3D camera
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

#pragma mark - World To Screen Projector

- (BOOL)projectWorldPos:(SCNVector3)worldPos toScreen:(ImVec2 &)outScreen distance:(float *)outDist
{
    SCNVector3 projected = [_scnView projectPoint:worldPos];
    if (projected.z <= 0.0f || projected.z >= 1.0f) return NO;

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

#pragma mark - Custom UI Widgets (Matching Reference Layout)

static bool ToggleSwitch(const char *label, bool *v)
{
    ImGuiWindow *window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return false;

    float height = 24.0f;
    float width = 46.0f;
    float radius = height * 0.5f;

    ImVec2 pos = ImGui::GetCursorScreenPos();
    float avail_w = ImGui::GetContentRegionAvail().x;

    // Label on Left
    ImGui::AlignTextToFramePadding();
    ImGui::TextColored(ImVec4(0.92f, 0.92f, 0.96f, 1.0f), "%s", label);

    // Clickable toggle button on Right
    ImGui::SameLine(avail_w - width);
    std::string btn_id = std::string("##switch_") + label;
    bool pressed = ImGui::InvisibleButton(btn_id.c_str(), ImVec2(width, height));
    if (pressed) {
        *v = !(*v);
    }

    ImVec2 btn_min = ImGui::GetItemRectMin();
    ImVec2 btn_max = ImGui::GetItemRectMax();

    // Background pill (#FF8A00 when ON, #32323F when OFF)
    ImU32 bg_col = *v ? ImColor(255, 138, 0, 255) : ImColor(50, 50, 63, 255);
    window->DrawList->AddRectFilled(btn_min, btn_max, bg_col, radius);

    // Sliding White Knob
    float knob_radius = radius - 2.5f;
    float t = *v ? 1.0f : 0.0f;
    float knob_x = btn_min.x + radius + t * (width - 2.0f * radius);
    ImVec2 knob_center(knob_x, btn_min.y + radius);

    // Subtle drop shadow + knob
    window->DrawList->AddCircleFilled(ImVec2(knob_center.x, knob_center.y + 1.0f), knob_radius, ImColor(0, 0, 0, 90), 16);
    window->DrawList->AddCircleFilled(knob_center, knob_radius, ImColor(255, 255, 255, 255), 16);

    return pressed;
}

static bool TuningSlider(const char *label, float *v, float v_min, float v_max, const char *unit_fmt = "%.1f")
{
    char val_buf[32];
    snprintf(val_buf, sizeof(val_buf), unit_fmt, *v);

    // Label on left, Value on right
    ImGui::TextColored(ImVec4(0.85f, 0.85f, 0.92f, 1.0f), "%s", label);
    float val_w = ImGui::CalcTextSize(val_buf).x;
    float avail_w = ImGui::GetContentRegionAvail().x;
    ImGui::SameLine(avail_w - val_w);
    ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "%s", val_buf);

    // Horizontal slider track
    ImGui::PushStyleColor(ImGuiCol_FrameBg, ImVec4(0.12f, 0.12f, 0.16f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_FrameBgActive, ImVec4(0.18f, 0.18f, 0.24f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_SliderGrab, ImVec4(1.0f, 0.54f, 0.0f, 1.0f)); // #FF8A00
    ImGui::PushStyleColor(ImGuiCol_SliderGrabActive, ImVec4(1.0f, 0.70f, 0.28f, 1.0f));
    ImGui::PushItemWidth(-1.0f);
    std::string slider_id = std::string("##slider_") + label;
    bool changed = ImGui::SliderFloat(slider_id.c_str(), v, v_min, v_max, "");
    ImGui::PopItemWidth();
    ImGui::PopStyleColor(4);

    return changed;
}

static void BeginCard(const char *title, float height = 0.0f)
{
    ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.125f, 0.125f, 0.168f, 0.85f)); // #20202B
    ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 10.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(14.0f, 12.0f));
    ImGui::BeginChild(title, ImVec2(0.0f, height), true, ImGuiWindowFlags_None);

    ImGui::TextColored(ImVec4(1.0f, 0.54f, 0.0f, 1.0f), ":: %s", title);
    ImGui::Spacing();
    ImGui::Separator();
    ImGui::Spacing();
}

static void EndCard()
{
    ImGui::EndChild();
    ImGui::PopStyleVar(2);
    ImGui::PopStyleColor();
}

#pragma mark - MTKView Delegate

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

    // 1. Draw ESP Telemetry Overlays
    if (g_State.bEnableESP) {
        [self drawESPOverlays];
    }

    // 2. Draw Aim FOV Circle & Lock Line
    if (g_State.bEnableAim) {
        ImDrawList *drawList = ImGui::GetBackgroundDrawList();
        ImVec2 center(io.DisplaySize.x / 2.0f, io.DisplaySize.y / 2.0f);
        drawList->AddCircle(center, g_State.fovRadius, ImColor(g_State.colFOV), 48, 1.8f);
        drawList->AddCircle(center, 2.5f, ImColor(g_State.colPrimaryOrange), 12, 2.0f);

        // Find closest target to aim circle for lock visualization
        if (g_State.bLockLine && !_dummies.empty()) {
            float closestDist = 9999.0f;
            ImVec2 targetScreen;
            bool found = false;

            for (const auto &d : _dummies) {
                SCNNode *head = [d.rootNode.presentationNode childNodeWithName:@"head" recursively:YES];
                SCNVector3 headWorld = head ? [head convertPosition:SCNVector3Zero toNode:nil] : SCNVector3Zero;
                ImVec2 s;
                if ([self projectWorldPos:headWorld toScreen:s distance:nil]) {
                    float dX = s.x - center.x;
                    float dY = s.y - center.y;
                    float screenDist = sqrtf(dX * dX + dY * dY);
                    if (screenDist < g_State.fovRadius && screenDist < closestDist) {
                        closestDist = screenDist;
                        targetScreen = s;
                        found = true;
                    }
                }
            }

            if (found) {
                drawList->AddLine(center, targetScreen, ImColor(g_State.colPrimaryOrange), 1.5f);
            }
        }
    }

    // 3. Render Modern OXSAK Interface
    if (g_ShowMenu) {
        [self renderOXSAKMenu];
    }

    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, renderEncoder);

    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}

#pragma mark - ESP Visual Rendering

- (void)drawESPOverlays
{
    ImDrawList *drawList = ImGui::GetBackgroundDrawList();
    ImGuiIO &io = ImGui::GetIO();
    float screenMidX = io.DisplaySize.x / 2.0f;
    float screenBottomY = io.DisplaySize.y;

    for (const auto &dummy : _dummies) {
        SCNNode *rootNode = dummy.rootNode.presentationNode;
        SCNVector3 rootWorld = [rootNode convertPosition:SCNVector3Zero toNode:nil];

        ImVec2 feetScr, headScr;
        float distance = 0.0f;
        if (![self projectWorldPos:rootWorld toScreen:feetScr distance:&distance]) continue;
        if (![self projectWorldPos:SCNVector3Make(rootWorld.x, rootWorld.y + g_State.headOffset, rootWorld.z) toScreen:headScr distance:nil]) continue;

        float topY = fminf(feetScr.y, headScr.y);
        float botY = fmaxf(feetScr.y, headScr.y);
        float height = botY - topY;
        if (height < 4.0f) continue;

        float width = height * g_State.boxWidthScale;
        float halfW = width / 2.0f;
        float centerX = (feetScr.x + headScr.x) / 2.0f;

        ImVec2 boxMin(centerX - halfW, topY);
        ImVec2 boxMax(centerX + halfW, botY);

        // 1. 2D Bounding Box
        if (g_State.bBox) {
            drawList->AddRect(boxMin, boxMax, ImColor(0, 0, 0, 220), 0.0f, 0, 3.0f);
            drawList->AddRect(boxMin, boxMax, ImColor(g_State.colBox), 0.0f, 0, 1.5f);
        }

        // 2. Snaplines
        if (g_State.bSnaplines) {
            drawList->AddLine(ImVec2(screenMidX, screenBottomY), ImVec2(centerX, botY), ImColor(g_State.colSnapline), 1.5f);
        }

        // 3. 15-Joint Humanoid Bone Skeleton
        if (g_State.bSkeleton) {
            auto GetBoneWorld = [&](NSString *boneName) -> SCNVector3 {
                SCNNode *bNode = [rootNode childNodeWithName:boneName recursively:YES];
                if (bNode) return [bNode convertPosition:SCNVector3Zero toNode:nil];
                return rootWorld;
            };

            auto DrawBoneLine = [&](NSString *b1, NSString *b2) {
                ImVec2 s1, s2;
                if ([self projectWorldPos:GetBoneWorld(b1) toScreen:s1 distance:nil] &&
                    [self projectWorldPos:GetBoneWorld(b2) toScreen:s2 distance:nil]) {
                    drawList->AddLine(s1, s2, ImColor(0, 0, 0, 220), 3.0f);
                    drawList->AddLine(s1, s2, ImColor(g_State.colSkeleton), 1.8f);
                }
            };

            // Head Circle
            ImVec2 headCenter;
            if ([self projectWorldPos:GetBoneWorld(@"head") toScreen:headCenter distance:nil]) {
                float headRadius = fmaxf(4.0f, height * 0.07f);
                drawList->AddCircle(headCenter, headRadius, ImColor(0, 0, 0, 220), 16, 3.0f);
                drawList->AddCircle(headCenter, headRadius, ImColor(g_State.colSkeleton), 16, 1.8f);
            }

            // Spine & Torso
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

        // 4. Health Bar
        if (g_State.bHealth) {
            float barW = 3.5f;
            float barMargin = 4.0f;
            ImVec2 bgMin(boxMin.x - barMargin - barW, boxMin.y);
            ImVec2 bgMax(boxMin.x - barMargin, boxMax.y);
            drawList->AddRectFilled(bgMin, bgMax, ImColor(0, 0, 0, 180));

            float hpRatio = fmaxf(0.0f, fminf(1.0f, dummy.health / dummy.maxHealth));
            float barFillHeight = height * hpRatio;
            ImVec2 fillMin(bgMin.x, bgMax.y - barFillHeight);
            ImVec4 hpCol = hpRatio > 0.5f ? ImVec4(0.0f, 1.0f, 0.3f, 1.0f) : ImVec4(1.0f, 0.2f, 0.0f, 1.0f);
            drawList->AddRectFilled(fillMin, bgMax, ImColor(hpCol));
        }

        // 5. Distance and Target Tag
        if (g_State.bDistance) {
            char label[64];
            snprintf(label, sizeof(label), "%s [%.0fm]", dummy.name.c_str(), distance);
            ImVec2 textSize = ImGui::CalcTextSize(label);
            ImVec2 textPos(centerX - (textSize.x / 2.0f), botY + 3.0f);

            drawList->AddText(ImVec2(textPos.x + 1, textPos.y + 1), ImColor(0, 0, 0, 220), label);
            drawList->AddText(textPos, ImColor(255, 255, 255, 255), label);
        }
    }
}

#pragma mark - OXSAK Modern Mobile Interface (Exact Match to Design Reference)

- (void)renderOXSAKMenu
{
    CGFloat screenW = self.view.bounds.size.width;
    CGFloat screenH = self.view.bounds.size.height;

    // Responsive scaling matching reference proportions
    CGFloat menuW = fminf(740.0f, screenW - 20.0f);
    CGFloat menuH = fminf(400.0f, screenH - 20.0f);
    if (screenW < 520.0f) {
        menuW = screenW - 16.0f;
        menuH = screenH - 36.0f;
    }

    ImGui::SetNextWindowSize(ImVec2(menuW, menuH), ImGuiCond_Always);
    ImGui::SetNextWindowPos(ImVec2((screenW - menuW) / 2.0f, (screenH - menuH) / 2.0f), ImGuiCond_Always);

    ImGuiWindowFlags winFlags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoScrollbar;

    if (ImGui::Begin("OXSAK_ROOT", &g_ShowMenu, winFlags)) {
        
        // =================================================================================
        // 1. LEFT VERTICAL SIDEBAR (#15151B)
        // =================================================================================
        float sidebarW = (screenW < 520.0f) ? 120.0f : 160.0f;
        ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.082f, 0.082f, 0.106f, 1.0f)); // #15151B
        ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 8.0f);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10.0f, 12.0f));
        ImGui::BeginChild("Sidebar", ImVec2(sidebarW, 0.0f), false);

        // Sidebar Logo / Title Header
        ImGui::Spacing();
        ImGui::TextColored(ImVec4(1.0f, 0.54f, 0.0f, 1.0f), "0xSAK");
        ImGui::SameLine();
        ImGui::TextColored(ImVec4(0.9f, 0.9f, 0.95f, 1.0f), "IOS");
        ImGui::Spacing();
        ImGui::Separator();
        ImGui::Spacing();

        // Vertical Navigation Tabs
        const char *tabs[] = { "Aimbot", "ESP", "Misc", "Settings" };
        const char *icons[] = { "(+)", "[#]", "{*}", "[=]" };

        for (int i = 0; i < 4; i++) {
            bool isActive = (g_State.currentTab == i);
            if (isActive) {
                ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(1.0f, 0.54f, 0.0f, 0.85f)); // Orange active pill
                ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 1.0f, 1.0f, 1.0f));
            } else {
                ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0)); // Transparent inactive
                ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.60f, 0.60f, 0.68f, 1.0f));
            }

            char tabLabel[64];
            snprintf(tabLabel, sizeof(tabLabel), "%s  %s", icons[i], tabs[i]);
            if (ImGui::Button(tabLabel, ImVec2(-1.0f, 38.0f))) {
                g_State.currentTab = i;
            }

            ImGui::PopStyleColor(2);
            ImGui::Spacing();
        }

        // Bottom [X] Close Button
        ImGui::SetCursorPosY(ImGui::GetWindowHeight() - 48.0f);
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.85f, 0.15f, 0.15f, 0.20f));
        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.35f, 0.35f, 1.0f));
        if (ImGui::Button("X  Close", ImVec2(-1.0f, 34.0f))) {
            g_ShowMenu = false;
        }
        ImGui::PopStyleColor(2);

        ImGui::EndChild();
        ImGui::PopStyleVar(2);
        ImGui::PopStyleColor();

        // =================================================================================
        // 2. MAIN CONTENT AREA (Next to Sidebar)
        // =================================================================================
        ImGui::SameLine();
        ImGui::BeginGroup();

        // Top Horizontal Sub-Tabs Bar
        ImGui::Spacing();
        if (g_State.currentTab == 0) {
            bool sub1 = (g_State.currentSubTab == 0);
            if (sub1) ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.70f, 0.28f, 1.0f));
            else      ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.55f, 0.55f, 0.65f, 1.0f));
            if (ImGui::Button("Aimbot (!)", ImVec2(120, 28))) g_State.currentSubTab = 0;
            ImGui::PopStyleColor();

            ImGui::SameLine();
            bool sub2 = (g_State.currentSubTab == 1);
            if (sub2) ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.70f, 0.28f, 1.0f));
            else      ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.55f, 0.55f, 0.65f, 1.0f));
            if (ImGui::Button("Silent Aim (!)", ImVec2(130, 28))) g_State.currentSubTab = 1;
            ImGui::PopStyleColor();
        } else if (g_State.currentTab == 1) {
            ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "Visuals & ESP Overlay");
        } else if (g_State.currentTab == 2) {
            ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "Diagnostics & Telemetry");
        } else {
            ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "Settings & Preferences");
        }

        ImGui::Separator();
        ImGui::Spacing();

        // Two-Column Content Area (Matching Reference Layout)
        float contentW = ImGui::GetContentRegionAvail().x;
        float colW = (contentW - 12.0f) * 0.5f;

        // ---------------------------------------------------------------------------------
        // TAB 0: AIMBOT / SILENT AIM (Two-Column Layout)
        // ---------------------------------------------------------------------------------
        if (g_State.currentTab == 0) {
            // Left Column: Toggles
            ImGui::BeginChild("AimLeftCol", ImVec2(colW, 0.0f), false);
            
            BeginCard("Aimbot", 165.0f);
            ToggleSwitch("Enable Aim", &g_State.bEnableAim);
            ImGui::Spacing();
            ToggleSwitch("Visible Only", &g_State.bVisibleOnly);
            ImGui::Spacing();
            ToggleSwitch("Ignore Team", &g_State.bIgnoreTeam);
            ImGui::Spacing();
            ToggleSwitch("Sticky", &g_State.bSticky);
            EndCard();

            ImGui::Spacing();
            BeginCard("Behavior", 0.0f);
            ToggleSwitch("Auto Shoot", &g_State.bAutoShoot);
            ImGui::Spacing();
            ToggleSwitch("Draw FOV Circle", &g_State.bLockLine);
            EndCard();

            ImGui::EndChild();

            // Right Column: Sliders & Tuning
            ImGui::SameLine();
            ImGui::BeginChild("AimRightCol", ImVec2(colW, 0.0f), false);

            BeginCard("Tuning", 0.0f);
            TuningSlider("FOV", &g_State.fovRadius, 10.0f, 300.0f, "%.0f");
            ImGui::Spacing();
            TuningSlider("Smoothness", &g_State.smoothness, 1.0f, 30.0f, "%.1f");
            ImGui::Spacing();
            TuningSlider("Max Turn", &g_State.maxTurn, 0.0f, 180.0f, "%.1f");
            ImGui::Spacing();
            TuningSlider("Reaction", &g_State.reactionMs, 0.0f, 500.0f, "%.0fms");
            ImGui::Spacing();
            TuningSlider("Jitter", &g_State.jitter, 0.0f, 0.5f, "%.2f");
            EndCard();

            ImGui::EndChild();
        }

        // ---------------------------------------------------------------------------------
        // TAB 1: ESP OVERLAYS (Two-Column Layout)
        // ---------------------------------------------------------------------------------
        else if (g_State.currentTab == 1) {
            ImGui::BeginChild("ESPLeftCol", ImVec2(colW, 0.0f), false);

            BeginCard("Visuals", 0.0f);
            ToggleSwitch("Master ESP", &g_State.bEnableESP);
            ImGui::Spacing();
            ToggleSwitch("15-Joint Skeleton", &g_State.bSkeleton);
            ImGui::Spacing();
            ToggleSwitch("2D Bounding Box", &g_State.bBox);
            ImGui::Spacing();
            ToggleSwitch("Snaplines", &g_State.bSnaplines);
            ImGui::Spacing();
            ToggleSwitch("Distance Tags", &g_State.bDistance);
            ImGui::Spacing();
            ToggleSwitch("Health Bars", &g_State.bHealth);
            EndCard();

            ImGui::EndChild();

            ImGui::SameLine();
            ImGui::BeginChild("ESPRightCol", ImVec2(colW, 0.0f), false);

            BeginCard("Calibration", 0.0f);
            TuningSlider("Head Offset", &g_State.headOffset, 0.8f, 2.5f, "%.2fm");
            ImGui::Spacing();
            TuningSlider("Box Width", &g_State.boxWidthScale, 0.2f, 0.8f, "%.2f");
            ImGui::Spacing();
            ImGui::Text("Active Target Count: %zu", _dummies.size());
            ImGui::Text("Skeleton Joints: 15 Bones Active");
            EndCard();

            ImGui::EndChild();
        }

        // ---------------------------------------------------------------------------------
        // TAB 2: MISC & TELEMETRY
        // ---------------------------------------------------------------------------------
        else if (g_State.currentTab == 2) {
            ImGui::BeginChild("MiscCol", ImVec2(0.0f, 0.0f), false);

            BeginCard("Scene Targets & Coordinates", 0.0f);
            for (size_t i = 0; i < _dummies.size(); i++) {
                const auto &d = _dummies[i];
                SCNVector3 pos = [d.rootNode.presentationNode convertPosition:SCNVector3Zero toNode:nil];
                ImGui::Text("[%zu] %s: (%.1f, %.1f, %.1f) - %.0f HP", i + 1, d.name.c_str(), pos.x, pos.y, pos.z, d.health);
            }
            ImGui::Separator();
            ImGui::Text("Framerate: %.1f FPS", ImGui::GetIO().Framerate);
            ImGui::Text("Display Size: %.0f x %.0f", ImGui::GetIO().DisplaySize.x, ImGui::GetIO().DisplaySize.y);
            ImGui::Text("Camera Distance: %.1fm", _cameraDistance);
            EndCard();

            ImGui::EndChild();
        }

        // ---------------------------------------------------------------------------------
        // TAB 3: SETTINGS
        // ---------------------------------------------------------------------------------
        else if (g_State.currentTab == 3) {
            ImGui::BeginChild("SettingsCol", ImVec2(0.0f, 0.0f), false);

            BeginCard("OXSAK Mobile Preferences", 0.0f);
            ImGui::TextColored(ImVec4(1.0f, 0.54f, 0.0f, 1.0f), "[ AUTHORIZED DEVELOPMENT SIMULATOR ]");
            ImGui::TextColored(ImVec4(0.6f, 0.6f, 0.7f, 1.0f), "Running standalone telemetry. Polyfield binary is untouched.");
            ImGui::Spacing();
            ImGui::BulletText("Tap 0xSAK Floating Badge to toggle menu");
            ImGui::BulletText("Drag 0xSAK Badge to relocate anywhere");
            ImGui::BulletText("Double-tap with 2 fingers anywhere to toggle");
            ImGui::BulletText("Swipe 1 finger to orbit 3D simulation camera");
            ImGui::BulletText("Pinch 2 fingers to zoom camera in and out");
            ImGui::Spacing();
            if (ImGui::Button("Reset Badge Position", ImVec2(180, 32))) {
                _floatingButton.center = CGPointMake(self.view.bounds.size.width - 45.0, 75.0);
            }
            EndCard();

            ImGui::EndChild();
        }

        ImGui::EndGroup();
    }
    ImGui::End();
}

@end

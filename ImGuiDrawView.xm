#import "Helper/x2nios.h"
#import "Esp/ImGuiDrawView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_internal.h"
#import "IMGUI/imgui_impl_metal.h"
#import "Esp/CaptainHook.h"
#import "Esp/PubgLoad.h"
#import "IMGUI/Honkai.h"
#import "5Toubun/NakanoIchika.h"
#import "5Toubun/NakanoNino.h"
#import "5Toubun/NakanoMiku.h"
#import "5Toubun/NakanoYotsuba.h"
#import "5Toubun/NakanoItsuki.h"
#import <Foundation/Foundation.h>
#import <os/log.h>
#import "pthread.h"
#include <math.h>
#include <deque>
#include <vector>
#include <fstream>
#include <string>

#include "Helper/Vector3.h"
#include "Helper/Vector2.h"
#include "Helper/Quaternion.h"
#include "Helper/Monostring.h"
#import <dlfcn.h>
#include <map>

#include <unistd.h>
#import "Helper/Functions/UniversalESP.h"
#include "fonts.h"
#import "Esp/oxsak_badge_data.h"

#define kWidth [UIScreen mainScreen].bounds.size.width
#define kHeight [UIScreen mainScreen].bounds.size.height
#define kScale [UIScreen mainScreen].scale

static bool MenDeal = true;
static id<MTLTexture> s_LogoTexture = nil;

// =========================================================================
// Navigation & State Management
// Sidebar: 0 = ESP, 1 = AIM, 2 = MISC, 3 = SETTING
// =========================================================================
static int s_SelectedTab = 0;       // 0: ESP, 1: AIM, 2: MISC, 3: SETTING
__attribute__((unused)) static int s_AimSubTab = 0;         // 0: AIMBOT, 1: SILENT AIM

// ── ESP Settings ──
static int s_BoxStyle = 0;          // 0: Square, 1: Corner

// ── Aimbot Settings ──
static bool s_AimEnable = false;
static bool s_AimVisibleOnly = true;
static bool s_AimIgnoreTeam = true;
static bool s_AimSticky = false;
static bool s_AimDrawFOV = true;
static float s_AimFOV = 70.0f;
static float s_AimSmoothness = 10.0f;
static float s_AimMaxTurn = 45.0f;
static float s_AimReaction = 20.0f;
static float s_AimJitter = 0.07f;

// ── Silent Aim Settings ──
static bool s_SilentEnable = false;
static bool s_SilentAutoFire = false;
static bool s_SilentHitchanceCheck = true;
static bool s_SilentIgnoreSleepers = true;
static float s_SilentFOV = 40.0f;
static float s_SilentHitchance = 85.0f;
static int s_SilentBone = 0;        // 0: Head, 1: Neck, 2: Chest, 3: Pelvis

// ── MISC Feature Toggles ──
// (Wired to existing g_bNoRecoil / g_bInfiniteAmmo in UniversalESP.h)
static bool s_NoRecoil       = false;
static bool s_NoSpread       = false;
static bool s_UnlimitedAmmo  = false;
static bool s_FastReload     = false;
static bool s_FastShoot      = false;
static bool s_OneHitKill     = false;
static bool s_SpeedHack      = false;
static float s_SpeedMultiplier = 1.0f;

// ── HUD & System ──
static bool s_ShowWatermark = true;
static bool s_ShowCrosshair = false;
static float s_CrosshairSize = 10.0f;
static ImVec4 s_CrosshairColor = ImVec4(1.0f, 0.54f, 0.0f, 0.9f);
static float s_MenuAlpha = 0.95f;

// =========================================================================
// Vector Navigation Icons
// High-DPI Resolution Independent Custom Rendered Icons
// =========================================================================
enum NavIcon {
	NAV_ICON_AIM,
	NAV_ICON_ESP,
	NAV_ICON_MISC,
	NAV_ICON_SETTING,
	NAV_ICON_CLOSE
};

static void DrawNavIcon(NavIcon icon, ImVec2 center, ImU32 col)
{
	ImDrawList* drawList = ImGui::GetWindowDrawList();

	switch (icon) {
		case NAV_ICON_AIM: {
			// Sniper Crosshair Icon
			drawList->AddCircle(center, 5.5f, col, 16, 1.2f);
			drawList->AddCircleFilled(center, 1.5f, col);
			// 4 Crosshair Tick Marks
			drawList->AddLine(ImVec2(center.x, center.y - 7.5f), ImVec2(center.x, center.y - 3.8f), col, 1.2f);
			drawList->AddLine(ImVec2(center.x, center.y + 3.8f), ImVec2(center.x, center.y + 7.5f), col, 1.2f);
			drawList->AddLine(ImVec2(center.x - 7.5f, center.y), ImVec2(center.x - 3.8f, center.y), col, 1.2f);
			drawList->AddLine(ImVec2(center.x + 3.8f, center.y), ImVec2(center.x + 7.5f, center.y), col, 1.2f);
			break;
		}
		case NAV_ICON_ESP: {
			// Eye Vision Icon (Bezier Curves)
			ImVec2 left(center.x - 7.2f, center.y);
			ImVec2 right(center.x + 7.2f, center.y);
			ImVec2 topCtrl(center.x, center.y - 5.0f);
			ImVec2 botCtrl(center.x, center.y + 5.0f);

			drawList->AddBezierQuadratic(left, topCtrl, right, col, 1.3f);
			drawList->AddBezierQuadratic(left, botCtrl, right, col, 1.3f);
			// Iris & Specular Highlight
			drawList->AddCircleFilled(center, 2.5f, col);
			drawList->AddCircleFilled(ImVec2(center.x + 0.9f, center.y - 0.9f), 0.8f, IM_COL32(255, 255, 255, 240));
			break;
		}
		case NAV_ICON_MISC: {
			// Tuning Sliders / Faders Icon
			float y1 = center.y - 4.5f;
			float y2 = center.y;
			float y3 = center.y + 4.5f;

			drawList->AddLine(ImVec2(center.x - 6.5f, y1), ImVec2(center.x + 6.5f, y1), col, 1.2f);
			drawList->AddCircleFilled(ImVec2(center.x - 2.0f, y1), 1.8f, col);

			drawList->AddLine(ImVec2(center.x - 6.5f, y2), ImVec2(center.x + 6.5f, y2), col, 1.2f);
			drawList->AddCircleFilled(ImVec2(center.x + 2.5f, y2), 1.8f, col);

			drawList->AddLine(ImVec2(center.x - 6.5f, y3), ImVec2(center.x + 6.5f, y3), col, 1.2f);
			drawList->AddCircleFilled(ImVec2(center.x - 3.5f, y3), 1.8f, col);
			break;
		}
		case NAV_ICON_SETTING: {
			// 6-Tooth Mechanical Gear Icon
			drawList->AddCircle(center, 3.2f, col, 16, 1.3f);
			const int teeth = 6;
			for (int i = 0; i < teeth; i++) {
				float a = (float)i * (2.0f * 3.14159265f / (float)teeth);
				float cosA = cosf(a);
				float sinA = sinf(a);
				ImVec2 p1(center.x + cosA * 3.8f, center.y + sinA * 3.8f);
				ImVec2 p2(center.x + cosA * 6.5f, center.y + sinA * 6.5f);
				drawList->AddLine(p1, p2, col, 1.8f);
			}
			break;
		}
		case NAV_ICON_CLOSE: {
			// Crisp Red Cross Mark
			drawList->AddLine(ImVec2(center.x - 4.5f, center.y - 4.5f), ImVec2(center.x + 4.5f, center.y + 4.5f), col, 1.5f);
			drawList->AddLine(ImVec2(center.x + 4.5f, center.y - 4.5f), ImVec2(center.x - 4.5f, center.y + 4.5f), col, 1.5f);
			break;
		}
	}
}

// Custom Navigation Button with Left-Aligned Icon and Label
static bool NavButton(const char* label, NavIcon icon, bool isSelected, float width = -1.0f, float height = 36.0f)
{
	ImGuiWindow* window = ImGui::GetCurrentWindow();
	if (window->SkipItems)
		return false;

	ImGuiContext& g = *GImGui;
	const ImGuiID id = window->GetID(label);

	ImVec2 pos = window->DC.CursorPos;
	float availW = ImGui::GetContentRegionAvail().x;
	ImVec2 size(width > 0 ? width : availW, height);
	const ImRect bb(pos, ImVec2(pos.x + size.x, pos.y + size.y));

	ImGui::ItemSize(size, 0.0f);
	if (!ImGui::ItemAdd(bb, id))
		return false;

	bool hovered, held;
	bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);

	ImU32 bg_col;
	ImU32 text_col;
	ImU32 icon_col;

	if (isSelected) {
		bg_col = IM_COL32(255, 138, 0, 240);    // Vibrant #FF8A00
		text_col = IM_COL32(10, 10, 14, 255);    // Dark contrasting text
		icon_col = IM_COL32(10, 10, 14, 255);    // Dark contrasting icon
	} else if (hovered || held) {
		bg_col = IM_COL32(36, 36, 48, 240);
		text_col = IM_COL32(255, 255, 255, 255);
		icon_col = IM_COL32(255, 179, 71, 240);  // Amber highlight
	} else {
		bg_col = IM_COL32(20, 20, 28, 220);      // Dark slate
		text_col = IM_COL32(215, 215, 225, 240); // Soft white
		icon_col = IM_COL32(255, 138, 0, 230);   // Primary Orange icon
	}

	ImDrawList* drawList = window->DrawList;
	drawList->AddRectFilled(bb.Min, bb.Max, bg_col, 6.0f);
	if (isSelected) {
		drawList->AddRect(bb.Min, bb.Max, IM_COL32(255, 179, 71, 200), 6.0f, 0, 1.2f);
	}

	// Render vector icon on the left
	ImVec2 iconCenter(bb.Min.x + 18.0f, bb.Min.y + height * 0.5f);
	DrawNavIcon(icon, iconCenter, icon_col);

	// Render text label next to the icon
	ImVec2 textPos(bb.Min.x + 36.0f, bb.Min.y + (height - ImGui::GetFontSize()) * 0.5f);
	drawList->AddText(textPos, text_col, label);

	return pressed;
}

// Sub-Tab Button (AIMBOT / SILENT AIM)
__attribute__((unused)) static bool SubTabButton(const char* label, NavIcon icon, bool isSelected, ImVec2 size)
{
	ImGuiWindow* window = ImGui::GetCurrentWindow();
	if (window->SkipItems)
		return false;

	const ImGuiID id = window->GetID(label);
	ImVec2 pos = window->DC.CursorPos;
	const ImRect bb(pos, ImVec2(pos.x + size.x, pos.y + size.y));

	ImGui::ItemSize(size, 0.0f);
	if (!ImGui::ItemAdd(bb, id))
		return false;

	bool hovered, held;
	bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);

	ImU32 bg_col = isSelected ? IM_COL32(255, 138, 0, 230) : (hovered ? IM_COL32(36, 36, 48, 220) : IM_COL32(24, 24, 32, 220));
	ImU32 text_col = isSelected ? IM_COL32(10, 10, 14, 255) : IM_COL32(220, 220, 230, 240);
	ImU32 icon_col = isSelected ? IM_COL32(10, 10, 14, 255) : IM_COL32(255, 138, 0, 220);

	ImDrawList* drawList = window->DrawList;
	drawList->AddRectFilled(bb.Min, bb.Max, bg_col, 5.0f);

	ImVec2 iconCenter(bb.Min.x + 16.0f, bb.Min.y + size.y * 0.5f);
	DrawNavIcon(icon, iconCenter, icon_col);

	ImVec2 textPos(bb.Min.x + 32.0f, bb.Min.y + (size.y - ImGui::GetFontSize()) * 0.5f);
	drawList->AddText(textPos, text_col, label);

	return pressed;
}

// =========================================================================
// Touch-Through Filter View
// Only intercepts touches that land directly inside active ImGui windows
// =========================================================================
@interface ImGuiTouchView : MTKView
@end

@implementation ImGuiTouchView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
	if (!MenDeal || !ImGui::GetCurrentContext()) {
		return NO; // Pass touch through to Polyfield when menu is closed
	}

	ImGuiContext *g = ImGui::GetCurrentContext();
	ImVec2 pt = ImVec2(point.x, point.y);

	for (int i = 0; i < g->Windows.Size; i++) {
		ImGuiWindow *window = g->Windows[i];
		if (!window || !window->WasActive || window->Hidden) continue;
		if (window->Flags & ImGuiWindowFlags_NoInputs) continue;

		// Check if touch point is inside the menu window bounding box
		if (pt.x >= window->Pos.x && pt.x <= (window->Pos.x + window->Size.x) &&
			pt.y >= window->Pos.y && pt.y <= (window->Pos.y + window->Size.y)) {
			return YES; // Menu captures the touch
		}
	}

	// Check if dropdown popup or color picker is open
	if (g->OpenPopupStack.Size > 0) {
		return YES;
	}

	return NO; // Outside menu -> Polyfield receives the touch!
}

@end

// =========================================================================
// Clean Modern iOS Toggle Switch Widget (#FF8A00 Active Orange)
// =========================================================================
static bool OXSAK_Toggle(const char* label, bool* v)
{
	ImVec2 p = ImGui::GetCursorScreenPos();
	ImDrawList* draw_list = ImGui::GetWindowDrawList();
	float height = 22.0f;
	float width = 42.0f;
	float radius = height * 0.5f;

	ImGui::InvisibleButton(label, ImVec2(width, height));
	if (ImGui::IsItemClicked()) {
		*v = !(*v);
	}

	float t = *v ? 1.0f : 0.0f;
	ImU32 col_bg = *v ? IM_COL32(255, 138, 0, 245) : IM_COL32(36, 36, 48, 240);
	draw_list->AddRectFilled(p, ImVec2(p.x + width, p.y + height), col_bg, radius);
	
	if (*v) {
		draw_list->AddRect(p, ImVec2(p.x + width, p.y + height), IM_COL32(255, 179, 71, 180), radius, 0, 1.0f);
	} else {
		draw_list->AddRect(p, ImVec2(p.x + width, p.y + height), IM_COL32(60, 60, 75, 180), radius, 0, 1.0f);
	}

	draw_list->AddCircleFilled(ImVec2(p.x + radius + t * (width - 2.0f * radius), p.y + radius), radius - 2.5f, IM_COL32(255, 255, 255, 255));

	ImGui::SameLine(0, 10.0f);
	ImGui::TextUnformatted(label);
	return *v;
}

@interface ImGuiDrawView () <MTKViewDelegate>
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation ImGuiDrawView

+ (id<MTLTexture>)createTextureFromImage:(UIImage *)image device:(id<MTLDevice>)device
{
	if (!image || !device) return nil;
	CGImageRef imageRef = image.CGImage;
	if (!imageRef) return nil;

	NSUInteger width = CGImageGetWidth(imageRef);
	NSUInteger height = CGImageGetHeight(imageRef);

	MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
																					 width:width
																					height:height
																				 mipmapped:NO];
	desc.usage = MTLTextureUsageShaderRead;
	id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
	if (!texture) return nil;

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	NSUInteger bytesPerPixel = 4;
	NSUInteger bytesPerRow = bytesPerPixel * width;
	NSUInteger bitsPerComponent = 8;

	void *rawData = calloc(height, bytesPerRow);
	if (!rawData) {
		CGColorSpaceRelease(colorSpace);
		return nil;
	}

	CGContextRef context = CGBitmapContextCreate(rawData, width, height,
												 bitsPerComponent, bytesPerRow, colorSpace,
												 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(colorSpace);

	if (context) {
		CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
		CGContextRelease(context);

		[texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
				   mipmapLevel:0
					 withBytes:rawData
				   bytesPerRow:bytesPerRow];
	}

	free(rawData);
	return texture;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
	self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];

	_device = MTLCreateSystemDefaultDevice();
	_commandQueue = [_device newCommandQueue];

	if (!self.device)
		abort();

	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO &io = ImGui::GetIO();
	(void)io;

	// =========================================================================
	// OXSAK Cyberpunk Orange & Charcoal Theme
	// =========================================================================
	ImGuiStyle &style = ImGui::GetStyle();
	style.WindowRounding = 10.0f;
	style.ChildRounding = 8.0f;
	style.FrameRounding = 6.0f;
	style.PopupRounding = 8.0f;
	style.ScrollbarRounding = 9.0f;
	style.GrabRounding = 5.0f;
	style.TabRounding = 6.0f;
	style.WindowBorderSize = 1.0f;
	style.FrameBorderSize = 0.5f;
	style.PopupBorderSize = 1.0f;
	style.WindowPadding = ImVec2(12, 12);
	style.FramePadding = ImVec2(10, 6);
	style.ItemSpacing = ImVec2(10, 8);
	style.ItemInnerSpacing = ImVec2(8, 6);

	ImVec4 *colors = style.Colors;
	colors[ImGuiCol_WindowBg] = ImVec4(0.063f, 0.063f, 0.078f, 0.95f);  // #101014
	colors[ImGuiCol_ChildBg] = ImVec4(0.125f, 0.125f, 0.169f, 0.85f);   // #20202B (Cards)
	colors[ImGuiCol_PopupBg] = ImVec4(0.082f, 0.082f, 0.106f, 0.98f);   // #15151B (Sidebar)
	colors[ImGuiCol_Border] = ImVec4(1.0f, 0.54f, 0.0f, 0.40f);         // #FF8A00 Subtle glow border
	colors[ImGuiCol_BorderShadow] = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);
	colors[ImGuiCol_FrameBg] = ImVec4(0.14f, 0.14f, 0.18f, 0.90f);
	colors[ImGuiCol_FrameBgHovered] = ImVec4(0.20f, 0.20f, 0.26f, 1.0f);
	colors[ImGuiCol_FrameBgActive] = ImVec4(1.0f, 0.54f, 0.0f, 0.35f);  // Orange active
	colors[ImGuiCol_TitleBg] = ImVec4(0.082f, 0.082f, 0.106f, 1.0f);
	colors[ImGuiCol_TitleBgActive] = ImVec4(0.082f, 0.082f, 0.106f, 1.0f);
	colors[ImGuiCol_TitleBgCollapsed] = ImVec4(0.082f, 0.082f, 0.106f, 1.0f);
	colors[ImGuiCol_CheckMark] = ImVec4(1.0f, 0.54f, 0.0f, 1.0f);       // #FF8A00
	colors[ImGuiCol_SliderGrab] = ImVec4(1.0f, 0.54f, 0.0f, 1.0f);      // #FF8A00
	colors[ImGuiCol_SliderGrabActive] = ImVec4(1.0f, 0.70f, 0.28f, 1.0f);// #FFB347
	colors[ImGuiCol_Button] = ImVec4(0.16f, 0.16f, 0.22f, 1.0f);
	colors[ImGuiCol_ButtonHovered] = ImVec4(1.0f, 0.54f, 0.0f, 0.35f);
	colors[ImGuiCol_ButtonActive] = ImVec4(1.0f, 0.54f, 0.0f, 0.65f);
	colors[ImGuiCol_Header] = ImVec4(1.0f, 0.54f, 0.0f, 0.25f);
	colors[ImGuiCol_HeaderHovered] = ImVec4(1.0f, 0.54f, 0.0f, 0.40f);
	colors[ImGuiCol_HeaderActive] = ImVec4(1.0f, 0.54f, 0.0f, 0.70f);
	colors[ImGuiCol_Tab] = ImVec4(0.12f, 0.12f, 0.16f, 1.0f);
	colors[ImGuiCol_TabHovered] = ImVec4(1.0f, 0.54f, 0.0f, 0.40f);
	colors[ImGuiCol_TabActive] = ImVec4(1.0f, 0.54f, 0.0f, 0.85f);
	colors[ImGuiCol_Text] = ImVec4(0.96f, 0.96f, 0.98f, 1.0f);          // Clean white
	colors[ImGuiCol_TextDisabled] = ImVec4(0.55f, 0.55f, 0.62f, 1.0f);  // Muted gray

	// Load Roboto Condensed embedded font directly from memory
	io.Fonts->AddFontFromMemoryTTF(roboto_regular, sizeof(roboto_regular), 18.0f, NULL, io.Fonts->GetGlyphRangesDefault());

	// Load the OXSAK logo emblem into a Metal texture for ImGui rendering
	NSData *imageData = [[NSData alloc] initWithBase64EncodedString:[NSString stringWithUTF8String:g_OXSAKBadgeBase64]
															options:NSDataBase64DecodingIgnoreUnknownCharacters];
	if (imageData) {
		UIImage *logoImg = [UIImage imageWithData:imageData];
		if (logoImg) {
			s_LogoTexture = [ImGuiDrawView createTextureFromImage:logoImg device:_device];
		}
	}

	ImGui_ImplMetal_Init(_device);

	return self;
}

+ (void)showChange:(BOOL)open
{
	MenDeal = open;
}

+ (BOOL)isMenuOpen
{
	return MenDeal;
}

+ (void)clearData
{
}

- (MTKView *)mtkView
{
	return (MTKView *)self.view;
}

- (void)loadView
{
	CGRect screenBounds = [UIScreen mainScreen].bounds;
	self.view = [[ImGuiTouchView alloc] initWithFrame:screenBounds];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.mtkView.device = self.device;
	self.mtkView.delegate = self;
	self.mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0);
	self.mtkView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
	self.mtkView.clipsToBounds = YES;
}

#pragma mark - Touch Interaction

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
	UITouch *anyTouch = event.allTouches.anyObject;
	CGPoint touchLocation = [anyTouch locationInView:self.view];
	ImGuiIO &io = ImGui::GetIO();
	io.MousePos = ImVec2(touchLocation.x, touchLocation.y);

	BOOL hasActiveTouch = NO;
	for (UITouch *touch in event.allTouches)
	{
		if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
		{
			hasActiveTouch = YES;
			break;
		}
	}
	io.MouseDown[0] = hasActiveTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[self updateIOWithTouchEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[self updateIOWithTouchEvent:event];
}

#pragma mark - Rendering Loop

- (void)drawInMTKView:(MTKView *)view
{
	ImGuiIO &io = ImGui::GetIO();
	io.DisplaySize.x = view.bounds.size.width;
	io.DisplaySize.y = view.bounds.size.height;
	CGFloat framebufferScale = view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
	io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
	io.DeltaTime = 1 / float(view.preferredFramesPerSecond ?: 60);

	id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

	MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
	if (renderPassDescriptor != nil)
	{
		id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
		[renderEncoder pushDebugGroup:@"OXSAK ImGui Menu"];

		ImGui_ImplMetal_NewFrame(renderPassDescriptor);
		ImGui::NewFrame();

		// Responsive layout sizing
		float screenW = io.DisplaySize.x;
		float screenH = io.DisplaySize.y;
		float winW = 640.0f;
		float winH = 360.0f;
		if (winW > screenW - 20.0f) winW = screenW - 20.0f;
		if (winH > screenH - 20.0f) winH = screenH - 20.0f;
		float posX = (screenW - winW) * 0.5f;
		float posY = (screenH - winH) * 0.5f;

		// Subtle watermark when menu is closed
		if (!MenDeal && s_ShowWatermark)
		{
			ImGui::SetNextWindowPos(ImVec2(screenW - 140.0f, 16.0f), ImGuiCond_Always);
			ImGui::SetNextWindowSize(ImVec2(125.0f, 28.0f), ImGuiCond_Always);
			ImGuiWindowFlags wmFlags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoBackground;
			if (ImGui::Begin("##Watermark", nullptr, wmFlags)) {
				ImGui::TextColored(ImVec4(1.0f, 0.54f, 0.0f, 0.85f), "OXSAK");
				ImGui::SameLine();
				ImGui::TextColored(ImVec4(0.8f, 0.8f, 0.8f, 0.6f), "Polyfield");
			}
			ImGui::End();
		}

		// Sync MISC toggles → engine variables
		g_bNoRecoil    = s_NoRecoil;
		g_bInfiniteAmmo = s_UnlimitedAmmo;

		if (MenDeal)
		{
			ImGui::SetNextWindowPos(ImVec2(posX, posY), ImGuiCond_FirstUseEver);
			ImGui::SetNextWindowSize(ImVec2(winW, winH), ImGuiCond_FirstUseEver);

			ImGuiWindowFlags winFlags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoTitleBar;
			ImGui::Begin("OXSAK_PANEL", &MenDeal, winFlags);

			// =================================================================
			// LEFT VERTICAL SIDEBAR (#15151B)
			// Navigation: ESP (Eye) | AIM (Crosshair) | MISC (Sliders) | SETTING (Gear)
			// =================================================================
			float sidebarW = 130.0f;
			ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.082f, 0.082f, 0.106f, 1.0f));
			ImGui::BeginChild("Sidebar", ImVec2(sidebarW, 0), true, ImGuiWindowFlags_NoScrollbar);
			{
				ImGui::Spacing();
				
				// Render the authentic graphic OXSAK emblem badge at the top
				if (s_LogoTexture) {
					float logoSize = 58.0f;
					float logoX = (sidebarW - logoSize) * 0.5f - 6.0f;
					if (logoX < 4.0f) logoX = 4.0f;
					ImGui::SetCursorPosX(logoX);
					ImGui::Image((__bridge void *)s_LogoTexture, ImVec2(logoSize, logoSize));
				}
				
				ImGui::Spacing();
				ImGui::Separator();
				ImGui::Spacing();

				// Navbar order: ESP → AIM → MISC → SETTING
				if (NavButton("ESP", NAV_ICON_ESP, s_SelectedTab == 0)) {
					s_SelectedTab = 0;
				}
				ImGui::Spacing();

				if (NavButton("AIM", NAV_ICON_AIM, s_SelectedTab == 1)) {
					s_SelectedTab = 1;
				}
				ImGui::Spacing();

				if (NavButton("MISC", NAV_ICON_MISC, s_SelectedTab == 2)) {
					s_SelectedTab = 2;
				}
				ImGui::Spacing();

				if (NavButton("SETTING", NAV_ICON_SETTING, s_SelectedTab == 3)) {
					s_SelectedTab = 3;
				}
				ImGui::Spacing();

				// Push Close Button to Bottom
				float availHeight = ImGui::GetContentRegionAvail().y;
				if (availHeight > 40.0f) {
					ImGui::Dummy(ImVec2(0, availHeight - 38.0f));
				}

				// Clean Close button with vector cross icon
				if (NavButton("Close", NAV_ICON_CLOSE, false, -1.0f, 30.0f)) {
					MenDeal = false;
					[ImGuiDrawView showChange:NO];
				}
			}
			ImGui::EndChild();
			ImGui::PopStyleColor();

			ImGui::SameLine();

			// =================================================================
			// RIGHT MAIN CONTENT AREA
			// =================================================================
			ImGui::BeginChild("ContentArea", ImVec2(0, 0), false);
			{
				// Card helper lambda — wraps content in a styled child region
				float contentW = ImGui::GetContentRegionAvail().x;
				float colW = (contentW - 12.0f) * 0.5f;

				// =============================================================
				// TAB 0: ESP
				// =============================================================
				if (s_SelectedTab == 0)
				{
					// ── Left Card: Box Configuration ──
					ImGui::BeginChild("ESP_Box_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "BOX");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Box", &g_ESP.bBox);
						if (g_ESP.bBox) {
							ImGui::Spacing();
							const char* boxStyles[] = { "Square", "Corner" };
							ImGui::SetNextItemWidth(-1.0f);
							if (ImGui::Combo("##BoxStyle", &s_BoxStyle, boxStyles, 2)) {
								g_ESP.bCornerBox = (s_BoxStyle == 1);
							}
							ImGui::Spacing();
							ImGui::Separator();
							ImGui::Spacing();

							ImGui::TextUnformatted("Head Offset");
							ImGui::SetNextItemWidth(-1.0f);
							ImGui::SliderFloat("##HeadOffset", &g_ESP.topPosFloat, 0.5f, 3.5f, "%.2f m");
							ImGui::Spacing();

							ImGui::TextUnformatted("Box Width");
							ImGui::SetNextItemWidth(-1.0f);
							ImGui::SliderFloat("##BoxWidth", &g_ESP.widthScale, 0.2f, 1.5f, "%.2f");
						}
					}
					ImGui::EndChild();

					ImGui::SameLine();

					// ── Right Card: Visual Elements & Diagnostics ──
					ImGui::BeginChild("ESP_Elements_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "ELEMENTS");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Snapline", &g_ESP.bLine);
						ImGui::Spacing();
						OXSAK_Toggle("Skeleton", &g_ESP.bSkeleton);
						ImGui::Spacing();
						OXSAK_Toggle("Distance", &g_ESP.bDistance);
						ImGui::Spacing();
						OXSAK_Toggle("Health", &g_ESP.bHealth);

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextColored(ImVec4(0.8f, 0.8f, 0.9f, 0.7f), "DIAGNOSTICS");
						ImGui::Spacing();
						ImGui::Text("NPCs: %d", g_NpcCount);
						ImGui::Text("Net Entities: %d", g_SpawnedNetCount);
						ImGui::Text("Local Player: %s", g_LocalPlayerPtr ? "Active" : "None");
						ImGui::Text("FPS: %.0f", io.Framerate);
					}
					ImGui::EndChild();
				}
				// =============================================================
				// TAB 1: AIM (Unified Two-Column Card Layout - No Top Sub-Tabs)
				// =============================================================
				else if (s_SelectedTab == 1)
				{
					// ── Left Card: Aimbot ──
					ImGui::BeginChild("Aim_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "AIMBOT");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Enable", &s_AimEnable);
						ImGui::Spacing();
						OXSAK_Toggle("Visible Check", &s_AimVisibleOnly);
						ImGui::Spacing();
						OXSAK_Toggle("Ignore Team", &s_AimIgnoreTeam);
						ImGui::Spacing();
						OXSAK_Toggle("Sticky Lock", &s_AimSticky);
						ImGui::Spacing();
						OXSAK_Toggle("Draw FOV", &s_AimDrawFOV);

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextUnformatted("FOV Radius");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##AimFOV", &s_AimFOV, 10.0f, 180.0f, "%.0f deg");
						ImGui::Spacing();

						ImGui::TextUnformatted("Smoothness");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##AimSmooth", &s_AimSmoothness, 1.0f, 30.0f, "%.1f");
					}
					ImGui::EndChild();

					ImGui::SameLine();

					// ── Right Card: Silent Aim ──
					ImGui::BeginChild("Silent_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "SILENT AIM");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Enable", &s_SilentEnable);
						ImGui::Spacing();
						OXSAK_Toggle("Auto Fire", &s_SilentAutoFire);
						ImGui::Spacing();
						OXSAK_Toggle("Hitchance Filter", &s_SilentHitchanceCheck);
						ImGui::Spacing();
						OXSAK_Toggle("Skip Dormant", &s_SilentIgnoreSleepers);

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextUnformatted("Silent FOV");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##SilentFOV", &s_SilentFOV, 5.0f, 90.0f, "%.0f deg");
						ImGui::Spacing();

						ImGui::TextUnformatted("Hitchance %");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##SilentHit", &s_SilentHitchance, 10.0f, 100.0f, "%.0f %%");
						ImGui::Spacing();

						ImGui::TextUnformatted("Target Bone");
						ImGui::SetNextItemWidth(-1.0f);
						const char* bones[] = { "Head", "Neck", "Chest", "Pelvis" };
						ImGui::Combo("##SilentBone", &s_SilentBone, bones, 4);
					}
					ImGui::EndChild();
				}
				// =============================================================
				// TAB 2: MISC (Combat & Utilities Cards)
				// =============================================================
				else if (s_SelectedTab == 2)
				{
					// ── Left Card: Combat Features ──
					ImGui::BeginChild("Misc_Combat_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "COMBAT");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("No Recoil", &s_NoRecoil);
						ImGui::Spacing();
						OXSAK_Toggle("No Spread", &s_NoSpread);
						ImGui::Spacing();
						OXSAK_Toggle("Unlimited Ammo", &s_UnlimitedAmmo);
						ImGui::Spacing();
						OXSAK_Toggle("Fast Reload", &s_FastReload);
						ImGui::Spacing();
						OXSAK_Toggle("Fast Shoot", &s_FastShoot);
						ImGui::Spacing();
						OXSAK_Toggle("1-Hit Kill", &s_OneHitKill);

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextColored(ImVec4(0.8f, 0.8f, 0.9f, 0.7f), "WEAPON STATUS");
						ImGui::Spacing();
						ImGui::Text("Ammo: %d", g_LiveWeaponAmmo);
						ImGui::Text("Mag: %d", g_LiveWeaponMag);
					}
					ImGui::EndChild();

					ImGui::SameLine();

					// ── Right Card: Player & HUD ──
					ImGui::BeginChild("Misc_Player_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "PLAYER & HUD");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Speed Hack", &s_SpeedHack);
						if (s_SpeedHack) {
							ImGui::Spacing();
							ImGui::TextUnformatted("Speed Multiplier");
							ImGui::SetNextItemWidth(-1.0f);
							ImGui::SliderFloat("##SpeedMult", &s_SpeedMultiplier, 1.0f, 5.0f, "%.1fx");
						}
						ImGui::Spacing();

						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Watermark", &s_ShowWatermark);
						ImGui::Spacing();
						OXSAK_Toggle("Crosshair", &s_ShowCrosshair);
						if (s_ShowCrosshair) {
							ImGui::Spacing();
							ImGui::TextUnformatted("Crosshair Size");
							ImGui::SetNextItemWidth(-1.0f);
							ImGui::SliderFloat("##ChSize", &s_CrosshairSize, 4.0f, 24.0f, "%.0f px");
							ImGui::Spacing();
							ImGui::ColorEdit4("Crosshair Color##ch", (float*)&s_CrosshairColor, ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_AlphaBar);
						}

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextColored(ImVec4(0.8f, 0.8f, 0.9f, 0.7f), "ENGINE METRICS");
						ImGui::Spacing();
						ImGui::Text("Resolution: %.0fx%.0f", io.DisplaySize.x, io.DisplaySize.y);
						ImGui::Text("Render: Apple MetalKit");
					}
					ImGui::EndChild();
				}
				// =============================================================
				// TAB 3: SETTING (Colors, Thinness, Snapline Origin, Theme)
				// =============================================================
				else if (s_SelectedTab == 3)
				{
					// ── Left Card: Appearance & Colors ──
					ImGui::BeginChild("Set_Colors_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "COLORS");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::ColorEdit4("Box##col", (float*)&g_ESP.boxColor, ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_AlphaBar);
						ImGui::Spacing();
						ImGui::ColorEdit4("Snapline##col", (float*)&g_ESP.lineColor, ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_AlphaBar);
						ImGui::Spacing();
						ImGui::ColorEdit4("Skeleton##col", (float*)&g_ESP.skeletonColor, ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_AlphaBar);

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "OUTLINE THINNESS");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextUnformatted("Box Thinness");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##BoxTh", &g_ESP.boxThickness, 0.5f, 3.0f, "%.1f px");
						ImGui::Spacing();

						ImGui::TextUnformatted("Snapline Thinness");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##LineTh", &g_ESP.lineThickness, 0.5f, 3.0f, "%.1f px");
						ImGui::Spacing();

						ImGui::TextUnformatted("Skeleton Thinness");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##SkelTh", &g_ESP.skeletonThickness, 0.5f, 3.0f, "%.1f px");
					}
					ImGui::EndChild();

					ImGui::SameLine();

					// ── Right Card: Display, Snapline Origin & Theme ──
					ImGui::BeginChild("Set_Prefs_Card", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "SNAPLINE ORIGIN");
						ImGui::Separator();
						ImGui::Spacing();

						const char* origins[] = { "Top", "Middle", "Bottom" };
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::Combo("##SnapOrigin", &g_ESP.lineOrigin, origins, 3);

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "THEME & OPACITY");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextUnformatted("Menu Opacity");
						ImGui::SetNextItemWidth(-1.0f);
						ImGui::SliderFloat("##MenuOpacity", &s_MenuAlpha, 0.50f, 1.00f, "%.2f");
						ImGui::GetStyle().Colors[ImGuiCol_WindowBg].w = s_MenuAlpha;

						ImGui::Spacing();
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "FLOATING LAUNCHER");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::Text("Dimensions: 56 x 56 pt");
						ImGui::Text("Border: Glowing #FF8A00");
						ImGui::Text("Memory: Saved to device");
						ImGui::Text("Gestures: Tap, Drag");
					}
					ImGui::EndChild();
				}
			}
			ImGui::EndChild();

			ImGui::End();
		}

		// Draw Crosshair on screen if enabled
		if (s_ShowCrosshair) {
			ImDrawList* drawList = ImGui::GetBackgroundDrawList();
			float midX = screenW * 0.5f;
			float midY = screenH * 0.5f;
			ImU32 col = ImColor(s_CrosshairColor);
			drawList->AddLine(ImVec2(midX - s_CrosshairSize, midY), ImVec2(midX + s_CrosshairSize, midY), col, 1.5f);
			drawList->AddLine(ImVec2(midX, midY - s_CrosshairSize), ImVec2(midX, midY + s_CrosshairSize), col, 1.5f);
		}

		// Draw ESP Line and Box overlay if enabled
		if (g_ESP.bEnable) {
			DrawUniversalESP();
		}

		ImGui::Render();
		ImDrawData *draw_data = ImGui::GetDrawData();
		ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);

		[renderEncoder popDebugGroup];
		[renderEncoder endEncoding];

		[commandBuffer presentDrawable:view.currentDrawable];
	}

	[commandBuffer commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
}

void hooking()
{
}

void *hack_thread(void *)
{
	sleep(5);
	hooking();
	pthread_exit(nullptr);
	return nullptr;
}

void __attribute__((constructor)) initialize()
{
}

@end

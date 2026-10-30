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

#define kWidth [UIScreen mainScreen].bounds.size.width
#define kHeight [UIScreen mainScreen].bounds.size.height
#define kScale [UIScreen mainScreen].scale

static bool MenDeal = true;

// =========================================================================
// OXSAK Visual State & Navigation (Isolated from Game Memory)
// =========================================================================
static int s_SelectedTab = 0;       // 0: AIMBOT, 1: SILENT AIM, 2: ESP, 3: MISC, 4: SETTINGS
static int s_AimbotSubTab = 0;      // 0: Aimbot, 1: Silent Aim

// Simulated Aimbot Telemetry Settings
static bool s_AimEnable = false;
static bool s_AimVisibleOnly = true;
static bool s_AimIgnoreTeam = true;
static bool s_AimSticky = false;
static float s_AimFOV = 70.0f;
static float s_AimSmoothness = 10.0f;
static float s_AimMaxTurn = 45.0f;
static float s_AimReaction = 20.0f;
static float s_AimJitter = 0.07f;

// Simulated Silent Aim Settings
static bool s_SilentEnable = false;
static bool s_SilentAutoFire = false;
static bool s_SilentHitchanceCheck = true;
static float s_SilentFOV = 40.0f;
static float s_SilentHitchance = 85.0f;
static int s_SilentBone = 0; // 0: Head, 1: Chest

// Visual ESP Configuration
static bool s_ESPEnable = false;
static bool s_ESPBox = true;
static bool s_ESPLine = false;
static bool s_ESPSkeleton = true;
static bool s_ESPDistance = true;
static bool s_ESPHealth = true;
static float s_HeadOffset = 1.80f;
static float s_FeetOffset = 0.10f;
static float s_WidthScale = 0.60f;

// Misc & System Diagnostics
static bool s_ShowWatermark = true;
static bool s_ShowCrosshair = false;
static float s_MenuAlpha = 0.95f;

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
// Custom iOS Toggle Switch Widget (#FF8A00 Active Orange)
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
	// #FF8A00 when ON, #20202B dark when OFF
	ImU32 col_bg = *v ? IM_COL32(255, 138, 0, 240) : IM_COL32(36, 36, 48, 240);
	draw_list->AddRectFilled(p, ImVec2(p.x + width, p.y + height), col_bg, radius);
	
	if (*v) {
		// Amber subtle outer highlight
		draw_list->AddRect(p, ImVec2(p.x + width, p.y + height), IM_COL32(255, 179, 71, 180), radius, 0, 1.0f);
	} else {
		draw_list->AddRect(p, ImVec2(p.x + width, p.y + height), IM_COL32(60, 60, 75, 180), radius, 0, 1.0f);
	}

	// White knob
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
	// OXSAK Cyberpunk Orange & Charcoal Design System
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
		float winW = 600.0f;
		float winH = 340.0f;
		if (winW > screenW - 20.0f) winW = screenW - 20.0f;
		if (winH > screenH - 20.0f) winH = screenH - 20.0f;
		float posX = (screenW - winW) * 0.5f;
		float posY = (screenH - winH) * 0.5f;

		// Subtle watermark when menu is closed
		if (!MenDeal && s_ShowWatermark)
		{
			ImGui::SetNextWindowPos(ImVec2(screenW - 160.0f, 16.0f), ImGuiCond_Always);
			ImGui::SetNextWindowSize(ImVec2(145.0f, 32.0f), ImGuiCond_Always);
			ImGuiWindowFlags wmFlags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoBackground;
			if (ImGui::Begin("##Watermark", nullptr, wmFlags)) {
				ImGui::TextColored(ImVec4(1.0f, 0.54f, 0.0f, 0.85f), "[OXSAK]");
				ImGui::SameLine();
				ImGui::TextColored(ImVec4(0.8f, 0.8f, 0.8f, 0.7f), "Polyfield");
			}
			ImGui::End();
		}

		if (MenDeal)
		{
			ImGui::SetNextWindowPos(ImVec2(posX, posY), ImGuiCond_FirstUseEver);
			ImGui::SetNextWindowSize(ImVec2(winW, winH), ImGuiCond_FirstUseEver);

			ImGuiWindowFlags winFlags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoTitleBar;
			ImGui::Begin("OXSAK_PANEL", &MenDeal, winFlags);

			// =================================================================
			// LEFT VERTICAL SIDEBAR (#15151B)
			// =================================================================
			float sidebarW = 125.0f;
			ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.082f, 0.082f, 0.106f, 1.0f));
			ImGui::BeginChild("Sidebar", ImVec2(sidebarW, 0), true, ImGuiWindowFlags_NoScrollbar);
			{
				ImGui::Spacing();
				ImGui::TextColored(ImVec4(1.0f, 0.54f, 0.0f, 1.0f), " OXSAK");
				ImGui::TextColored(ImVec4(0.6f, 0.6f, 0.7f, 0.8f), " POLYFIELD");
				ImGui::Separator();
				ImGui::Spacing();

				const char* tabNames[] = { "AIMBOT", "SILENT AIM", "ESP", "MISC", "SETTINGS" };
				for (int i = 0; i < 5; i++)
				{
					bool isSelected = (s_SelectedTab == i);
					if (isSelected) {
						ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(1.0f, 0.54f, 0.0f, 0.90f));
						ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.05f, 0.05f, 0.05f, 1.0f));
					} else {
						ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.12f, 0.12f, 0.16f, 0.80f));
						ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.85f, 0.85f, 0.90f, 1.0f));
					}

					if (ImGui::Button(tabNames[i], ImVec2(-1, 32))) {
						s_SelectedTab = i;
					}
					ImGui::PopStyleColor(2);
					ImGui::Spacing();
				}

				// Push Close Button to Bottom
				float availHeight = ImGui::GetContentRegionAvail().y;
				if (availHeight > 40.0f) {
					ImGui::Dummy(ImVec2(0, availHeight - 38.0f));
				}

				// Red styled Close button
				ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.85f, 0.15f, 0.15f, 0.25f));
				ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(1.0f, 0.25f, 0.25f, 0.80f));
				ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.40f, 0.40f, 1.0f));
				if (ImGui::Button("Close Menu", ImVec2(-1, 32))) {
					MenDeal = false;
					[ImGuiDrawView showChange:NO];
				}
				ImGui::PopStyleColor(3);
			}
			ImGui::EndChild();
			ImGui::PopStyleColor();

			ImGui::SameLine();

			// =================================================================
			// RIGHT MAIN CONTENT AREA
			// =================================================================
			ImGui::BeginChild("ContentArea", ImVec2(0, 0), false);
			{
				// Top Horizontal Sub-Tabs (when AIMBOT is active)
				if (s_SelectedTab == 0)
				{
					if (s_AimbotSubTab == 0) {
						ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(1.0f, 0.54f, 0.0f, 0.80f));
						ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.05f, 0.05f, 0.05f, 1.0f));
					} else {
						ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.15f, 0.15f, 0.20f, 0.80f));
						ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.85f, 0.85f, 0.90f, 1.0f));
					}
					if (ImGui::Button("Aimbot Telemetry", ImVec2(140, 28))) {
						s_AimbotSubTab = 0;
					}
					ImGui::PopStyleColor(2);

					ImGui::SameLine();

					if (s_AimbotSubTab == 1) {
						ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(1.0f, 0.54f, 0.0f, 0.80f));
						ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.05f, 0.05f, 0.05f, 1.0f));
					} else {
						ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.15f, 0.15f, 0.20f, 0.80f));
						ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.85f, 0.85f, 0.90f, 1.0f));
					}
					if (ImGui::Button("Silent Aim Telemetry", ImVec2(150, 28))) {
						s_AimbotSubTab = 1;
					}
					ImGui::PopStyleColor(2);

					ImGui::Separator();
				}

				// Two-Column Card Layout
				float colW = (ImGui::GetContentRegionAvail().x - 12.0f) * 0.5f;

				// -------------------------------------------------------------
				// TAB 0: AIMBOT
				// -------------------------------------------------------------
				if (s_SelectedTab == 0)
				{
					if (s_AimbotSubTab == 0)
					{
						// Column 1: Toggles
						ImGui::BeginChild("AimToggles", ImVec2(colW, 0), true);
						{
							ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] AIMBOT CONTROLS");
							ImGui::Separator();
							ImGui::Spacing();

							OXSAK_Toggle("Enable Aim", &s_AimEnable);
							ImGui::Spacing();
							OXSAK_Toggle("Visible Only", &s_AimVisibleOnly);
							ImGui::Spacing();
							OXSAK_Toggle("Ignore Team", &s_AimIgnoreTeam);
							ImGui::Spacing();
							OXSAK_Toggle("Sticky Lock", &s_AimSticky);
						}
						ImGui::EndChild();

						ImGui::SameLine();

						// Column 2: Sliders
						ImGui::BeginChild("AimSliders", ImVec2(colW, 0), true);
						{
							ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] TUNING & CALIBRATION");
							ImGui::Separator();
							ImGui::Spacing();

							ImGui::SliderFloat("FOV", &s_AimFOV, 10.0f, 180.0f, "%.0f deg");
							ImGui::Spacing();
							ImGui::SliderFloat("Smoothness", &s_AimSmoothness, 1.0f, 30.0f, "%.1f");
							ImGui::Spacing();
							ImGui::SliderFloat("Max Turn", &s_AimMaxTurn, 0.0f, 100.0f, "%.1f");
							ImGui::Spacing();
							ImGui::SliderFloat("Reaction", &s_AimReaction, 0.0f, 100.0f, "%.0f ms");
							ImGui::Spacing();
							ImGui::SliderFloat("Jitter", &s_AimJitter, 0.0f, 0.30f, "%.2f");
						}
						ImGui::EndChild();
					}
					else
					{
						// Column 1: Silent Aim Toggles
						ImGui::BeginChild("SilentToggles", ImVec2(colW, 0), true);
						{
							ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] SILENT AIM CONTROLS");
							ImGui::Separator();
							ImGui::Spacing();

							OXSAK_Toggle("Enable Silent Aim", &s_SilentEnable);
							ImGui::Spacing();
							OXSAK_Toggle("Auto Fire", &s_SilentAutoFire);
							ImGui::Spacing();
							OXSAK_Toggle("Hitchance Filter", &s_SilentHitchanceCheck);
						}
						ImGui::EndChild();

						ImGui::SameLine();

						// Column 2: Silent Aim Sliders
						ImGui::BeginChild("SilentSliders", ImVec2(colW, 0), true);
						{
							ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] SILENT TUNING");
							ImGui::Separator();
							ImGui::Spacing();

							ImGui::SliderFloat("Silent FOV", &s_SilentFOV, 5.0f, 90.0f, "%.0f deg");
							ImGui::Spacing();
							ImGui::SliderFloat("Hitchance", &s_SilentHitchance, 10.0f, 100.0f, "%.0f %%");
							ImGui::Spacing();
							const char* bones[] = { "Head", "Chest", "Pelvis" };
							ImGui::Combo("Target Bone", &s_SilentBone, bones, 3);
						}
						ImGui::EndChild();
					}
				}
				// -------------------------------------------------------------
				// TAB 1: SILENT AIM DIRECT TAB
				// -------------------------------------------------------------
				else if (s_SelectedTab == 1)
				{
					ImGui::BeginChild("SilentCol1", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] SILENT AIM CONTROLS");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Enable Silent Aim", &s_SilentEnable);
						ImGui::Spacing();
						OXSAK_Toggle("Auto Fire", &s_SilentAutoFire);
						ImGui::Spacing();
						OXSAK_Toggle("Hitchance Filter", &s_SilentHitchanceCheck);
					}
					ImGui::EndChild();

					ImGui::SameLine();

					ImGui::BeginChild("SilentCol2", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] SILENT TUNING");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::SliderFloat("Silent FOV", &s_SilentFOV, 5.0f, 90.0f, "%.0f deg");
						ImGui::Spacing();
						ImGui::SliderFloat("Hitchance", &s_SilentHitchance, 10.0f, 100.0f, "%.0f %%");
						ImGui::Spacing();
						const char* bones[] = { "Head", "Chest", "Pelvis" };
						ImGui::Combo("Target Bone", &s_SilentBone, bones, 3);
					}
					ImGui::EndChild();
				}
				// -------------------------------------------------------------
				// TAB 2: ESP
				// -------------------------------------------------------------
				else if (s_SelectedTab == 2)
				{
					ImGui::BeginChild("ESPToggles", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] ESP DISPLAY ELEMENTS");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Enable ESP Overlay", &s_ESPEnable);
						ImGui::Spacing();
						OXSAK_Toggle("2D Box ESP", &s_ESPBox);
						ImGui::Spacing();
						OXSAK_Toggle("Snaplines", &s_ESPLine);
						ImGui::Spacing();
						OXSAK_Toggle("Skeleton / Bones", &s_ESPSkeleton);
						ImGui::Spacing();
						OXSAK_Toggle("Distance Indicator", &s_ESPDistance);
						ImGui::Spacing();
						OXSAK_Toggle("Health Bar", &s_ESPHealth);
					}
					ImGui::EndChild();

					ImGui::SameLine();

					ImGui::BeginChild("ESPSliders", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] ESP CALIBRATION");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::SliderFloat("Head Offset", &s_HeadOffset, 0.5f, 3.5f, "%.2f m");
						ImGui::Spacing();
						ImGui::SliderFloat("Feet Offset", &s_FeetOffset, -1.0f, 1.0f, "%.2f m");
						ImGui::Spacing();
						ImGui::SliderFloat("Box Width Scale", &s_WidthScale, 0.2f, 1.5f, "%.2f");
						ImGui::Spacing();
						ImGui::Separator();
						ImGui::TextColored(ImVec4(0.8f, 0.8f, 0.9f, 1.0f), "ESP Visual Mode: Simulated");
					}
					ImGui::EndChild();
				}
				// -------------------------------------------------------------
				// TAB 3: MISC
				// -------------------------------------------------------------
				else if (s_SelectedTab == 3)
				{
					ImGui::BeginChild("MiscCol1", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] ENGINE METRICS");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::Text("Screen Resolution: %.0f x %.0f", io.DisplaySize.x, io.DisplaySize.y);
						ImGui::Text("Framerate: %.1f FPS", io.Framerate);
						ImGui::Text("Interface Mode: Polyfield Injected MTKView");
						ImGui::Text("Touch Filter: Selective pointInside");
					}
					ImGui::EndChild();

					ImGui::SameLine();

					ImGui::BeginChild("MiscCol2", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] VISUAL OVERLAYS");
						ImGui::Separator();
						ImGui::Spacing();

						OXSAK_Toggle("Show Top Watermark", &s_ShowWatermark);
						ImGui::Spacing();
						OXSAK_Toggle("Show Screen Crosshair", &s_ShowCrosshair);
					}
					ImGui::EndChild();
				}
				// -------------------------------------------------------------
				// TAB 4: SETTINGS
				// -------------------------------------------------------------
				else if (s_SelectedTab == 4)
				{
					ImGui::BeginChild("SettingsCol1", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] LAUNCHER CONFIGURATION");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::Text("Badge Dimensions: 56 x 56 pt");
						ImGui::Text("Launcher Glow: Enabled (#FF8A00)");
						ImGui::Text("Persistence: NSUserDefaults");
						ImGui::Text("Gesture: Tap or 2-Finger Double Tap");
					}
					ImGui::EndChild();

					ImGui::SameLine();

					ImGui::BeginChild("SettingsCol2", ImVec2(colW, 0), true);
					{
						ImGui::TextColored(ImVec4(1.0f, 0.70f, 0.28f, 1.0f), "[=] THEME TUNING");
						ImGui::Separator();
						ImGui::Spacing();

						ImGui::SliderFloat("Menu Opacity", &s_MenuAlpha, 0.50f, 1.00f, "%.2f");
						ImGui::GetStyle().Colors[ImGuiCol_WindowBg].w = s_MenuAlpha;
					}
					ImGui::EndChild();
				}
			}
			ImGui::EndChild();

			ImGui::End();
		}

		// Connect safe visual ESP state to engine
		g_ESP.bEnable = s_ESPEnable;
		g_ESP.bBox = s_ESPBox;
		g_ESP.bLine = s_ESPLine;
		g_ESP.bSkeleton = s_ESPSkeleton;
		g_ESP.bDistance = s_ESPDistance;
		g_ESP.topPosFloat = s_HeadOffset;
		g_ESP.botPosFloat = s_FeetOffset;
		g_ESP.widthScale = s_WidthScale;

		if (s_ESPEnable) {
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

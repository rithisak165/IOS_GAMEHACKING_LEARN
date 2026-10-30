#import "Helper/x2nios.h"
#import "Esp/ImGuiDrawView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>
#import "Esp/ImGuiDrawView.h"
#import "IMGUI/imgui.h"
#import "IMGUI/imgui_internal.h"
#import "IMGUI/imgui_impl_metal.h"
#import "Esp/CaptainHook.h"
#import "Esp/PubgLoad.h"
#import "IMGUI/Honkai.h"
//Patch library
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


#include "Helper/Vector3.h"
#include "Helper/Vector2.h"
#include "Helper/Quaternion.h"
#include "Helper/Monostring.h"
#include <vector>
#import <dlfcn.h>
#include <map>

#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

#include <unistd.h>
#import "Helper/Functions/UniversalESP.h"

#define kWidth [UIScreen mainScreen].bounds.size.width
#define kHeight [UIScreen mainScreen].bounds.size.height
#define kScale [UIScreen mainScreen].scale
#define kTest   0 


static bool MenDeal = true;

@interface ImGuiTouchView : MTKView
@end

@implementation ImGuiTouchView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
	if (!MenDeal || !ImGui::GetCurrentContext()) {
		return NO; // Pass touch through to the game when menu is closed
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

	return NO; // Outside menu -> game receives the touch!
}

@end

@interface ImGuiDrawView () <MTKViewDelegate>
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation ImGuiDrawView

ImFont *verdanab;
ImFont *icons;
ImFont *interb;
ImFont *Urbanist;

#define BundlePath @"/Library/PreferenceBundles/Tweak.bundle"
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

	ImGui::StyleColorsDark();
	auto &Style = ImGui::GetStyle();

	NSString *FontPath = @"/System/Library/Fonts/Core/Helvetica.ttc";
	if ([[NSFileManager defaultManager] fileExistsAtPath:FontPath]) {
		io.Fonts->AddFontFromFileTTF(FontPath.UTF8String, 24.f, NULL, io.Fonts->GetGlyphRangesDefault());
	} else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/System/Library/Fonts/AppFonts/Charter.ttc"]) {
		io.Fonts->AddFontFromFileTTF("/System/Library/Fonts/AppFonts/Charter.ttc", 24.f, NULL, io.Fonts->GetGlyphRangesDefault());
	} else {
		io.Fonts->AddFontDefault();
	}

	ImGui_ImplMetal_Init(_device);

	return self;
}

+ (void)showChange:(BOOL)open
{
	MenDeal = open;
}

static UITextField *Norecord;

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

void ColorPicker(const char *name, ImVec4 &color)
{
	static ImVec4 backup_color;

	bool open_popup = ImGui::ColorButton((std::string(name) + std::string("##3b")).c_str(), color);
	// open_popup |= ImGui::Button("Palette");
	if (open_popup)
	{
		ImGui::OpenPopup(name);
		backup_color = color;
	}
	if (ImGui::BeginPopup(name))
	{
		ImGui::Spacing();
		ImGui::Text("Select Color");
		ImGui::Separator();
		ImGui::ColorPicker4("##picker", (float *)&color, ImGuiColorEditFlags_NoSidePreview | ImGuiColorEditFlags_NoSmallPreview);
		ImGui::SameLine();

		ImGui::BeginGroup(); // Lock X position
		ImGui::Text("Current");
		ImGui::ColorButton("##current", color,
						   ImGuiColorEditFlags_NoPicker | ImGuiColorEditFlags_AlphaPreviewHalf,
						   ImVec2(60, 40));
		ImGui::Text("Previous");
		if (ImGui::ColorButton("##previous", backup_color, ImGuiColorEditFlags_NoPicker | ImGuiColorEditFlags_AlphaPreviewHalf, ImVec2(60, 40)))
		{
			color = backup_color;
		}
		ImGui::EndGroup();
		ImGui::EndPopup();
	}
}

#pragma mark - Interaction

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
		[renderEncoder pushDebugGroup:@"ImGui Jane"];

		ImGui_ImplMetal_NewFrame(renderPassDescriptor);
		ImGui::NewFrame();
		ImFont *font = ImGui::GetFont();
		font->Scale = 16.f / font->FontSize;

		CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
		CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
		CGFloat x = (screenWidth - 320.0f) / 2.0f;
		CGFloat y = (screenHeight - 220.0f) / 2.0f;

		ImGui::SetNextWindowPos(ImVec2(x, y), ImGuiCond_FirstUseEver);
		ImGui::SetNextWindowSize(ImVec2(320.0f, 220.0f), ImGuiCond_FirstUseEver);

		if (MenDeal)
		{
			ImGui::SetNextWindowSize(ImVec2(340.0f, 260.0f), ImGuiCond_FirstUseEver);
			ImGui::Begin("Polyfield Universal ESP", &MenDeal, ImGuiWindowFlags_None);

			if (ImGui::BeginTabBar("Tabs"))
			{
				if (ImGui::BeginTabItem("ESP"))
				{
					ImGui::Checkbox("Enable ESP", &g_ESP.bEnable);
					ImGui::Separator();

					ImGui::Checkbox("Box ESP", &g_ESP.bBox);
					ImGui::SameLine();
					ColorPicker("##BoxColor", g_ESP.boxColor);

					ImGui::Checkbox("Line ESP", &g_ESP.bLine);
					ImGui::SameLine();
					ColorPicker("##LineColor", g_ESP.lineColor);

					ImGui::Checkbox("Distance ESP", &g_ESP.bDistance);

					ImGui::Checkbox("Draw Local Player (Self Check)", &g_ESP.bDrawSelf);

					ImGui::Separator();
					ImGui::TextColored(ImVec4(1, 0.8f, 0.2f, 1), "=== WEAPON MEMORY MODS ===");
					ImGui::Checkbox("No Recoil", &g_bNoRecoil);
					ImGui::Checkbox("Infinite Ammo", &g_bInfiniteAmmo);

					ImGui::EndTabItem();
				}

				if (ImGui::BeginTabItem("Debug / Advanced"))
				{
					ImGui::TextColored(ImVec4(0, 1, 0, 1), "=== ENGINE STATUS ===");
					void* cam = Camera_get_main ? Camera_get_main() : nullptr;
					ImGui::Text("Camera: %s (0x%llx)", cam ? "ACTIVE" : "NULL", (uint64_t)cam);
					ImGui::Text("Local Player: %s (0x%llx)", g_LocalPlayerPtr ? "IN MATCH" : "LOBBY/RESPAWN", (uint64_t)g_LocalPlayerPtr);
					ImGui::Text("Unity Resolution: %.0f x %.0f", g_UnityScreenWidth, g_UnityScreenHeight);
					ImGui::Text("ImGui Display: %.0f x %.0f (%.1f FPS)", 
								ImGui::GetIO().DisplaySize.x, 
								ImGui::GetIO().DisplaySize.y, 
								ImGui::GetIO().Framerate);

					ImGui::Separator();
					ImGui::TextColored(ImVec4(0.4f, 0.9f, 1.0f, 1), "=== MEMORY ENTITY SCANNER ===");
					ImGui::Text("Bot Matches (NpcManager): %d bots found", g_NpcCount);
					ImGui::Text("Network (Mirror.Spawned): %d entities", g_SpawnedNetCount);
					ImGui::Text("Active ESP Targets: %zu", g_EntityList.size());

					ImGui::Separator();
					ImGui::TextColored(ImVec4(1, 0.7f, 0.2f, 1), "=== WEAPON DIAGNOSTICS ===");
					if (g_LiveWeaponPtr) {
						ImGui::TextColored(ImVec4(0, 1, 0, 1), "Weapon: ACTIVE (0x%llx)", (uint64_t)g_LiveWeaponPtr);
						ImGui::TextColored(ImVec4(0, 1, 0, 1), "Live Ammo: %d | Reserve: %d", g_LiveWeaponAmmo, g_LiveWeaponMag);
					} else {
						ImGui::TextColored(ImVec4(1, 1, 0, 1), "Weapon: (Hold weapon in-game to read)");
					}

					ImGui::Separator();
					ImGui::TextColored(ImVec4(0.4f, 0.8f, 1.0f, 1), "=== BOX CALIBRATION ===");
					ImGui::SliderFloat("Head Offset (topPos)", &g_ESP.topPosFloat, 0.5f, 4.0f, "%.2f m");
					ImGui::SliderFloat("Feet Offset (botPos)", &g_ESP.botPosFloat, -1.0f, 1.0f, "%.2f m");
					ImGui::SliderFloat("Width Scale", &g_ESP.widthScale, 0.1f, 1.5f, "%.2f");

					ImGui::Separator();
					ImGui::TextColored(ImVec4(1, 0.8f, 0.2f, 1), "=== ENTITY INSPECTOR ===");
					std::vector<void*> snapshot;
					{
						std::lock_guard<std::mutex> lock(g_EntityMutex);
						snapshot = g_EntityList;
					}

					if (snapshot.empty()) {
						ImGui::TextColored(ImVec4(1, 1, 0, 1), "Waiting for bots / players to spawn in match...");
					} else {
						for (size_t i = 0; i < snapshot.size() && i < 6; i++) {
							void* ent = snapshot[i];
							if (!IsValidPtr(ent)) continue;
							void* tr = Component_get_transform ? Component_get_transform(ent) : nullptr;
							if (!IsValidPtr(tr)) continue;
							Vector3 pos = Transform_get_position(tr);
							ImVec2 scr;
							bool onScreen = WorldToScreen(pos, scr);
							ImGui::Text("[%zu] Pos:(%.1f, %.1f, %.1f) %s", 
										i, pos.x, pos.y, pos.z,
										onScreen ? "ON SCREEN" : "OFF SCREEN");
						}
					}

					ImGui::EndTabItem();
				}
				ImGui::EndTabBar();
			}
			ImGui::End();
		}

		// Draw ESP Line and Box overlay (updates memory entities automatically)
		DrawUniversalESP();

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
	// PubgLoad +load is triggered automatically by dyld; duplicate call removed to prevent double menu
}

@end

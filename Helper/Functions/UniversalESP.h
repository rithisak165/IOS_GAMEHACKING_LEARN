#pragma once

#include <vector>
#include <algorithm>
#include <cmath>
#include <string>
#include <mutex>
#import <UIKit/UIKit.h>

#include "IMGUI/imgui.h"
#include "Helper/Vector3.h"
#include "Helper/Vector2.h"
#include "Helper/x2nios.h"

// =========================================================================================
// UNIVERSAL UNITY IL2CPP ESP & MEMORY ENGINE (iOS Jailed & Sideloaded Safe)
// -----------------------------------------------------------------------------------------
// Designed for Polyfield (com.MA.PF).
// 100% PURE POINTER TRAVERSAL & MEMORY ACCESS - NO FUNCTION HOOKS (ZERO CRASHES).
// Reads static Il2CppClass TypeInfo metadata to dynamically locate:
//   1. NpcManager.npcs (Bot matches)
//   2. PlayerControl.Local (Local player & Weapon Combat)
//   3. Mirror.NetworkClient.spawned (Multiplayer & Network entities)
// =========================================================================================

// =========================================================================================
// 1. CONFIGURATION: RVA OFFSETS (From Polyfield_Dump/dump.cs & script.json)
// =========================================================================================

// Unity Engine Functions
#define OFFSET_CAMERA_GET_MAIN         0x4846D64  // UnityEngine.Camera::get_main()
#define OFFSET_CAMERA_WORLDTOSCREEN    0x48469F0  // UnityEngine.Camera::WorldToScreenPoint(Vector3)
#define OFFSET_COMPONENT_GET_TRANSFORM 0x4872A68  // UnityEngine.Component::get_transform()
#define OFFSET_TRANSFORM_GET_POSITION  0x4881060  // UnityEngine.Transform::get_position()
#define OFFSET_SCREEN_GET_WIDTH        0x4850F54  // UnityEngine.Screen::get_width()
#define OFFSET_SCREEN_GET_HEIGHT       0x4850F94  // UnityEngine.Screen::get_height()

// Polyfield IL2CPP TypeInfo Offsets (script.json)
#define TYPEINFO_NPC_MANAGER           0x6318990  // NpcManager_TypeInfo (holds static Dictionary<string, NpcControl> npcs)
#define TYPEINFO_PLAYER_CONTROL        0x6318D50  // PlayerControl_TypeInfo (holds static <Local>k__BackingField)
#define TYPEINFO_NETWORK_CLIENT        0x63187D0  // Mirror.NetworkClient_TypeInfo (holds static Dictionary<uint, NetworkIdentity> spawned)

// Polyfield Direct Method RVAs
#define RVA_PLAYER_GET_LOCAL           0x3197290  // PlayerControl::get_Local()
#define RVA_PLAYER_COMBAT_GET_INV      0x318FEFC  // PlayerCombat::GetCurrLocalInventory()

// =========================================================================================
// 2. UNITY ENGINE FUNCTION POINTERS
// =========================================================================================
void*   (*Camera_get_main)() = nullptr;
Vector3 (*Camera_WorldToScreenPoint)(void* camera, Vector3 worldPos) = nullptr;
void*   (*Component_get_transform)(void* component) = nullptr;
Vector3 (*Transform_get_position)(void* transform) = nullptr;
void*   (*PlayerControl_get_Local)() = nullptr;
int     (*Screen_get_width)() = nullptr;
int     (*Screen_get_height)() = nullptr;

// =========================================================================================
// 3. USER INTERFACE SETTINGS
// =========================================================================================
struct ESPSettings {
    bool   bEnable      = false;                     // Master ESP toggle
    bool   bBox         = true;                      // 2D Bounding Box
    bool   bCornerBox   = false;                     // Corner Box Style
    bool   bLine        = true;                      // Snapline to feet
    int    lineOrigin   = 0;                         // 0: Bottom, 1: Center, 2: Top
    bool   bDistance    = true;                      // Distance text
    bool   bSkeleton    = true;                      // 15-Joint Humanoid Skeleton ESP
    bool   bHealth      = true;                      // Health Bar
    bool   bDrawSelf    = false;                     // Draw box on local player (diagnostic)
    float  topPosFloat  = 1.85f;                     // Head offset (height in meters)
    float  botPosFloat  = 0.00f;                     // Feet offset
    float  widthScale   = 0.50f;                     // Width multiplier
    float  boxThickness = 1.0f;                      // Box outline thickness (thin default)
    float  lineThickness = 1.0f;                     // Snapline thickness (thin default)
    float  skeletonThickness = 1.0f;                 // Skeleton thickness (thin default)
    ImVec4 boxColor     = ImColor(255, 138, 0, 255);  // #FF8A00 Orange default
    ImVec4 lineColor    = ImColor(255, 179, 71, 220); // #FFB347 Amber default
    ImVec4 skeletonColor = ImColor(255, 255, 255, 240); // White
} g_ESP;

// Safe memory probe to prevent EXC_BAD_ACCESS crashes
inline bool IsValidPtr(void* ptr) {
    if (!ptr) return false;
    uintptr_t addr = (uintptr_t)ptr;
    // Standard 64-bit userland range on iOS
    if (addr < 0x100000000ULL || addr > 0x3000000000ULL) return false;
    char probe[8];
    return (KittyMemory::memRead(probe, ptr, sizeof(probe)) == KittyMemory::SUCCESS);
}

// =========================================================================================
// 4. ENTITY & WEAPON STATE
// =========================================================================================
std::vector<void*> g_EntityList;
std::mutex         g_EntityMutex;

// Live diagnostics for the Debug UI tab
int      g_NpcCount          = 0;
int      g_SpawnedNetCount   = 0;
void*    g_LocalPlayerPtr    = nullptr;
void*    g_LiveWeaponPtr     = nullptr;
int      g_LiveWeaponAmmo    = -1;
int      g_LiveWeaponMag     = -1;
bool     g_bNoRecoil         = false;
bool     g_bInfiniteAmmo     = false;
float    g_UnityScreenWidth  = 0.0f;
float    g_UnityScreenHeight = 0.0f;

// Helper to get active rendering camera (prefer player's local camera, fallback to Camera.main)
inline void* GetActiveCamera() {
    if (IsValidPtr(g_LocalPlayerPtr)) {
        void* localCam = *(void**)((uintptr_t)g_LocalPlayerPtr + 0x170); // PlayerControl::localCamera
        if (IsValidPtr(localCam)) return localCam;
    }
    if (Camera_get_main) {
        void* mainCam = Camera_get_main();
        if (IsValidPtr(mainCam)) return mainCam;
    }
    return nullptr;
}

// =========================================================================================
// 5. POINTER-BASED ENTITY & WEAPON SCANNER (Pure Memory - No Hooks)
// =========================================================================================
void UpdateEntitiesAndFeatures() {
    // 1. Resolve Unity Engine Function Pointers
    if (!Camera_get_main) {
        Camera_get_main           = (void* (*)())getRealOffset(OFFSET_CAMERA_GET_MAIN);
        Camera_WorldToScreenPoint = (Vector3 (*)(void*, Vector3))getRealOffset(OFFSET_CAMERA_WORLDTOSCREEN);
        Component_get_transform   = (void* (*)(void*))getRealOffset(OFFSET_COMPONENT_GET_TRANSFORM);
        Transform_get_position    = (Vector3 (*)(void*))getRealOffset(OFFSET_TRANSFORM_GET_POSITION);
        PlayerControl_get_Local   = (void* (*)())getRealOffset(RVA_PLAYER_GET_LOCAL);
        Screen_get_width          = (int (*)())getRealOffset(OFFSET_SCREEN_GET_WIDTH);
        Screen_get_height         = (int (*)())getRealOffset(OFFSET_SCREEN_GET_HEIGHT);
    }

    std::vector<void*> newEntities;

    // 2. Resolve Local Player
    void* localPlayer = nullptr;
    if (PlayerControl_get_Local) {
        localPlayer = PlayerControl_get_Local();
    }
    if (!IsValidPtr(localPlayer)) {
        // Fallback: Read TypeInfo static field directly
        uintptr_t pcKlassAddr = getRealOffset(TYPEINFO_PLAYER_CONTROL);
        if (IsValidPtr((void*)pcKlassAddr)) {
            void* pcKlass = *(void**)pcKlassAddr;
            if (IsValidPtr(pcKlass)) {
                void* statics = *(void**)((uintptr_t)pcKlass + 0xB8);
                if (IsValidPtr(statics)) {
                    localPlayer = *(void**)statics;
                }
            }
        }
    }
    g_LocalPlayerPtr = localPlayer;

    if (IsValidPtr(localPlayer) && g_ESP.bDrawSelf) {
        newEntities.push_back(localPlayer);
    }

    // 3. Process Weapon & Combat Modifications (No Recoil & Infinite Ammo)
    if (IsValidPtr(localPlayer)) {
        void* combat = *(void**)((uintptr_t)localPlayer + 0x278); // PlayerControl::playerCombat
        if (IsValidPtr(combat)) {
            // No Recoil: Zero out weapon kick & recoil spring
            if (g_bNoRecoil) {
                *(Vector3*)((uintptr_t)combat + 0xBC) = Vector3(0.0f, 0.0f, 0.0f); // weaponKick
                *(Vector2*)((uintptr_t)combat + 0xD0) = Vector2(0.0f, 0.0f);       // recoilSpring
            }

            // Get Current Weapon from inventory list
            void* invList = *(void**)((uintptr_t)combat + 0x80); // PlayerCombat::inventory (List<InventoryItem>)
            int currIdx = *(int*)((uintptr_t)combat + 0x7C);     // currentInventoryItem
            if (IsValidPtr(invList)) {
                void* itemsArray = *(void**)((uintptr_t)invList + 0x10);
                int size = *(int*)((uintptr_t)invList + 0x18);
                if (IsValidPtr(itemsArray) && currIdx >= 0 && currIdx < size) {
                    void* invItem = *(void**)((uintptr_t)itemsArray + 0x20 + (currIdx * sizeof(void*)));
                    if (IsValidPtr(invItem)) {
                        void* weapon = *(void**)((uintptr_t)invItem + 0x18); // InventoryItem::weapon
                        if (IsValidPtr(weapon)) {
                            g_LiveWeaponPtr  = weapon;
                            g_LiveWeaponAmmo = *(int*)((uintptr_t)weapon + 0xC4);
                            g_LiveWeaponMag  = *(int*)((uintptr_t)weapon + 0xC8);

                            if (g_bInfiniteAmmo) {
                                *(int*)((uintptr_t)weapon + 0xC4) = 99;  // ammo
                                *(int*)((uintptr_t)weapon + 0xC8) = 999; // mag
                            }
                            if (g_bNoRecoil) {
                                *(Vector3*)((uintptr_t)weapon + 0xA8) = Vector3(0.0f, 0.0f, 0.0f); // forces
                            }
                        }
                    }
                }
            }
        }
    } else {
        g_LiveWeaponPtr  = nullptr;
        g_LiveWeaponAmmo = -1;
        g_LiveWeaponMag  = -1;
    }

    // 4. Scan Bot Enemies from NpcManager.npcs (Static Dictionary)
    g_NpcCount = 0;
    uintptr_t npcKlassAddr = getRealOffset(TYPEINFO_NPC_MANAGER);
    if (IsValidPtr((void*)npcKlassAddr)) {
        void* npcKlass = *(void**)npcKlassAddr;
        if (IsValidPtr(npcKlass)) {
            void* statics = *(void**)((uintptr_t)npcKlass + 0xB8);
            if (IsValidPtr(statics)) {
                void* npcsDict = *(void**)((uintptr_t)statics + 0x8); // NpcManager.npcs (Dictionary<string, NpcControl>)
                if (IsValidPtr(npcsDict)) {
                    void* entriesArray = *(void**)((uintptr_t)npcsDict + 0x18); // _entries
                    int32_t count = *(int32_t*)((uintptr_t)npcsDict + 0x20);     // _count
                    if (IsValidPtr(entriesArray) && count > 0 && count < 128) {
                        g_NpcCount = count;
                        for (int32_t i = 0; i < count; i++) {
                            // Entry<string, NpcControl>: { int hashCode; int next; string key; NpcControl* value; }
                            uintptr_t entryAddr = ((uintptr_t)entriesArray + 0x20) + (i * 0x18);
                            int32_t hashCode = *(int32_t*)entryAddr;
                            if (hashCode >= 0) { // Non-empty entry in .NET Dictionary
                                void* npc = *(void**)(entryAddr + 0x10);
                                if (IsValidPtr(npc)) {
                                    // Check if dead (NpcControl::dead is at 0x7C)
                                    bool isDead = *(bool*)((uintptr_t)npc + 0x7C);
                                    if (!isDead) {
                                        newEntities.push_back(npc);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 5. Scan Network Entities from Mirror.NetworkClient.spawned (Static Dictionary)
    g_SpawnedNetCount = 0;
    uintptr_t ncKlassAddr = getRealOffset(TYPEINFO_NETWORK_CLIENT);
    if (IsValidPtr((void*)ncKlassAddr)) {
        void* ncKlass = *(void**)ncKlassAddr;
        if (IsValidPtr(ncKlass)) {
            void* statics = *(void**)((uintptr_t)ncKlass + 0xB8);
            if (IsValidPtr(statics)) {
                void* spawnedDict = *(void**)((uintptr_t)statics + 0x18); // NetworkClient.spawned (Dictionary<uint, NetworkIdentity>)
                if (IsValidPtr(spawnedDict)) {
                    void* entriesArray = *(void**)((uintptr_t)spawnedDict + 0x18);
                    int32_t count = *(int32_t*)((uintptr_t)spawnedDict + 0x20);
                    if (IsValidPtr(entriesArray) && count > 0 && count < 256) {
                        g_SpawnedNetCount = count;
                        for (int32_t i = 0; i < count; i++) {
                            // Entry<uint, NetworkIdentity>: { int hashCode; int next; uint key; pad; NetworkIdentity* value; }
                            uintptr_t entryAddr = ((uintptr_t)entriesArray + 0x20) + (i * 0x18);
                            int32_t hashCode = *(int32_t*)entryAddr;
                            if (hashCode >= 0) {
                                void* identity = *(void**)(entryAddr + 0x10);
                                if (IsValidPtr(identity) && identity != localPlayer) {
                                    // Only add if not already in list
                                    if (std::find(newEntities.begin(), newEntities.end(), identity) == newEntities.end()) {
                                        newEntities.push_back(identity);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Update global list atomically
    {
        std::lock_guard<std::mutex> lock(g_EntityMutex);
        g_EntityList = std::move(newEntities);
    }
}

// =========================================================================================
// 6. ACCURATE WORLD-TO-SCREEN PROJECTION
// -----------------------------------------------------------------------------------------
// Maps 3D world coordinates (X, Y, Z) to 2D pixel coordinates (X, Y) on the iOS display.
// Converts Unity Native Screen Pixels to ImGui UI Display Points.
// Returns false if target is behind camera.
// =========================================================================================
bool WorldToScreen(Vector3 worldPos, ImVec2 &outScreen, float* outDist = nullptr) {
    void* cam = GetActiveCamera();
    if (!IsValidPtr(cam) || !Camera_WorldToScreenPoint) return false;

    // Call Unity Camera.WorldToScreenPoint(Vector3)
    Vector3 screen = Camera_WorldToScreenPoint(cam, worldPos);

    // Behind camera check: Z is distance along the camera axis in world units (meters)
    if (screen.z <= 0.1f) return false;

    if (outDist) *outDist = screen.z;

    // Resolve Unity native screen resolution
    float uWidth  = Screen_get_width  ? (float)Screen_get_width()  : 0.0f;
    float uHeight = Screen_get_height ? (float)Screen_get_height() : 0.0f;

    // Fallback if Screen.get_width/height returned 0
    if (uWidth <= 0.0f || uHeight <= 0.0f) {
        float scale = ImGui::GetIO().DisplayFramebufferScale.x;
        if (scale < 1.0f) scale = 1.0f;
        uWidth  = ImGui::GetIO().DisplaySize.x * scale;
        uHeight = ImGui::GetIO().DisplaySize.y * scale;
    }

    g_UnityScreenWidth  = uWidth;
    g_UnityScreenHeight = uHeight;

    // 1. Normalize Unity Screen coordinates to [0.0 .. 1.0] range
    float normX = screen.x / uWidth;
    float normY = screen.y / uHeight;

    // 2. Map normalized coordinates to ImGui Display Points
    // Unity origin (0, 0) is BOTTOM-LEFT; ImGui origin (0, 0) is TOP-LEFT.
    float displayW = ImGui::GetIO().DisplaySize.x;
    float displayH = ImGui::GetIO().DisplaySize.y;

    outScreen.x = normX * displayW;
    outScreen.y = displayH - (normY * displayH);

    return true;
}

// =========================================================================================
// 7. DRAWING LOGIC (Executed every frame inside MTKView)
// =========================================================================================
void DrawUniversalESP() {
    // 1. Run memory scan & features update
    UpdateEntitiesAndFeatures();

    if (!g_ESP.bEnable) return;
    if (!Camera_WorldToScreenPoint) return;
    if (!Component_get_transform || !Transform_get_position) return;

    void* cam = GetActiveCamera();
    if (!IsValidPtr(cam)) return;

    // Take snapshot under lock for thread safety
    std::vector<void*> snapshot;
    {
        std::lock_guard<std::mutex> lock(g_EntityMutex);
        snapshot = g_EntityList;
    }

    if (snapshot.empty()) return;

    ImDrawList* drawList = ImGui::GetBackgroundDrawList();
    float screenMidX    = ImGui::GetIO().DisplaySize.x / 2.0f;
    float screenBottomY = ImGui::GetIO().DisplaySize.y;
    float dispW         = ImGui::GetIO().DisplaySize.x;
    float dispH         = ImGui::GetIO().DisplaySize.y;

    for (void* entity : snapshot) {
        if (!IsValidPtr(entity)) continue;

        void* transform = Component_get_transform(entity);
        if (!IsValidPtr(transform)) continue;

        // 1. Get 3D position of actor root (feet)
        Vector3 rootPos = Transform_get_position(transform);

        // Sanity check coordinates (prevent NaN or astronomical floats)
        if (std::isnan(rootPos.x) || std::isnan(rootPos.y) || std::isnan(rootPos.z)) continue;
        if (std::fabs(rootPos.x) > 5000.0f || std::fabs(rootPos.z) > 5000.0f) continue;

        // 2. Project Feet (root + botPosFloat) and Head (root + topPosFloat) onto 2D screen
        ImVec2 feetPos, headPos;
        float distance = 0.0f;
        if (!WorldToScreen(rootPos + Vector3(0, g_ESP.botPosFloat, 0), feetPos, &distance)) continue;
        if (!WorldToScreen(rootPos + Vector3(0, g_ESP.topPosFloat, 0), headPos)) continue;

        // 3. Calculate 2D Bounding Box Dimensions
        float topY = fminf(feetPos.y, headPos.y);
        float botY = fmaxf(feetPos.y, headPos.y);
        float height = botY - topY;
        if (height < 3.0f || height > 2000.0f) continue;

        float width     = height * g_ESP.widthScale;
        float halfWidth = width / 2.0f;
        float centerX   = (feetPos.x + headPos.x) / 2.0f;

        ImVec2 boxMin(centerX - halfWidth, topY); // Top-Left
        ImVec2 boxMax(centerX + halfWidth, botY); // Bottom-Right

        // Cull targets completely outside the display viewport
        if (boxMax.x < -100.0f || boxMin.x > dispW + 100.0f ||
            boxMax.y < -100.0f || boxMin.y > dispH + 100.0f) {
            continue;
        }

        // 4. Draw Bounding Box (Normal or Corner Box)
        if (g_ESP.bBox) {
            float th = fmaxf(0.5f, g_ESP.boxThickness);
            if (g_ESP.bCornerBox) {
                // Pro Corner Box
                float cornerLen = fminf(width * 0.25f, height * 0.25f);
                // Top-Left
                drawList->AddLine(boxMin, ImVec2(boxMin.x + cornerLen, boxMin.y), ImColor(g_ESP.boxColor), th);
                drawList->AddLine(boxMin, ImVec2(boxMin.x, boxMin.y + cornerLen), ImColor(g_ESP.boxColor), th);
                // Top-Right
                drawList->AddLine(ImVec2(boxMax.x, boxMin.y), ImVec2(boxMax.x - cornerLen, boxMin.y), ImColor(g_ESP.boxColor), th);
                drawList->AddLine(ImVec2(boxMax.x, boxMin.y), ImVec2(boxMax.x, boxMin.y + cornerLen), ImColor(g_ESP.boxColor), th);
                // Bottom-Left
                drawList->AddLine(ImVec2(boxMin.x, boxMax.y), ImVec2(boxMin.x + cornerLen, boxMax.y), ImColor(g_ESP.boxColor), th);
                drawList->AddLine(ImVec2(boxMin.x, boxMax.y), ImVec2(boxMin.x, boxMax.y - cornerLen), ImColor(g_ESP.boxColor), th);
                // Bottom-Right
                drawList->AddLine(boxMax, ImVec2(boxMax.x - cornerLen, boxMax.y), ImColor(g_ESP.boxColor), th);
                drawList->AddLine(boxMax, ImVec2(boxMax.x, boxMax.y - cornerLen), ImColor(g_ESP.boxColor), th);
            } else {
                // Clean Full Box with subtle dark shadow
                drawList->AddRect(boxMin, boxMax, ImColor(0, 0, 0, 160), 0.0f, 0, th + 1.0f);
                drawList->AddRect(boxMin, boxMax, ImColor(g_ESP.boxColor), 0.0f, 0, th);
            }
        }

        // 5. Draw Snapline
        if (g_ESP.bLine) {
            float startY = screenBottomY;
            if (g_ESP.lineOrigin == 1) startY = dispH * 0.5f;
            else if (g_ESP.lineOrigin == 2) startY = 0.0f;

            float th = fmaxf(0.5f, g_ESP.lineThickness);
            drawList->AddLine(ImVec2(screenMidX, startY), ImVec2(centerX, botY), ImColor(0, 0, 0, 160), th + 1.0f);
            drawList->AddLine(ImVec2(screenMidX, startY), ImVec2(centerX, botY), ImColor(g_ESP.lineColor), th);
        }

        // 6. Draw 15-Joint Humanoid Bone Skeleton
        if (g_ESP.bSkeleton) {
            float H = g_ESP.topPosFloat - g_ESP.botPosFloat;
            if (H < 1.0f) H = 1.8f;
            float W = H * 0.22f;

            // Define 15 Joint coordinates in 3D world space
            Vector3 head3D   = rootPos + Vector3(0.0f, H * 0.95f, 0.0f);
            Vector3 neck3D   = rootPos + Vector3(0.0f, H * 0.82f, 0.0f);
            Vector3 spine3D  = rootPos + Vector3(0.0f, H * 0.65f, 0.0f);
            Vector3 pelvis3D = rootPos + Vector3(0.0f, H * 0.50f, 0.0f);

            // Left Arm
            Vector3 lShoulder3D = rootPos + Vector3(-W * 1.1f, H * 0.80f, 0.0f);
            Vector3 lElbow3D    = rootPos + Vector3(-W * 1.4f, H * 0.58f, 0.0f);
            Vector3 lHand3D     = rootPos + Vector3(-W * 1.5f, H * 0.38f, 0.0f);

            // Right Arm
            Vector3 rShoulder3D = rootPos + Vector3(W * 1.1f, H * 0.80f, 0.0f);
            Vector3 rElbow3D    = rootPos + Vector3(W * 1.4f, H * 0.58f, 0.0f);
            Vector3 rHand3D     = rootPos + Vector3(W * 1.5f, H * 0.38f, 0.0f);

            // Left Leg
            Vector3 lHip3D   = rootPos + Vector3(-W * 0.55f, H * 0.48f, 0.0f);
            Vector3 lKnee3D  = rootPos + Vector3(-W * 0.60f, H * 0.26f, 0.0f);
            Vector3 lFoot3D  = rootPos + Vector3(-W * 0.65f, H * 0.02f, 0.0f);

            // Right Leg
            Vector3 rHip3D   = rootPos + Vector3(W * 0.55f, H * 0.48f, 0.0f);
            Vector3 rKnee3D  = rootPos + Vector3(W * 0.60f, H * 0.26f, 0.0f);
            Vector3 rFoot3D  = rootPos + Vector3(W * 0.65f, H * 0.02f, 0.0f);

            // Lambda to project and draw an outlined bone segment
            float th = fmaxf(0.5f, g_ESP.skeletonThickness);
            auto DrawBone = [&](const Vector3& p1, const Vector3& p2) {
                ImVec2 s1, s2;
                if (WorldToScreen(p1, s1) && WorldToScreen(p2, s2)) {
                    drawList->AddLine(s1, s2, ImColor(0, 0, 0, 160), th + 1.0f);
                    drawList->AddLine(s1, s2, ImColor(g_ESP.skeletonColor), th);
                }
            };

            // Head Circle
            ImVec2 sHead;
            if (WorldToScreen(head3D, sHead)) {
                float headRadius = fmaxf(3.0f, height * 0.065f);
                drawList->AddCircle(sHead, headRadius, ImColor(0, 0, 0, 220), 16, 2.5f);
                drawList->AddCircle(sHead, headRadius, ImColor(g_ESP.skeletonColor), 16, 1.5f);
            }

            // Torso / Spine
            DrawBone(head3D, neck3D);
            DrawBone(neck3D, spine3D);
            DrawBone(spine3D, pelvis3D);

            // Left Arm
            DrawBone(neck3D, lShoulder3D);
            DrawBone(lShoulder3D, lElbow3D);
            DrawBone(lElbow3D, lHand3D);

            // Right Arm
            DrawBone(neck3D, rShoulder3D);
            DrawBone(rShoulder3D, rElbow3D);
            DrawBone(rElbow3D, rHand3D);

            // Left Leg
            DrawBone(pelvis3D, lHip3D);
            DrawBone(lHip3D, lKnee3D);
            DrawBone(lKnee3D, lFoot3D);

            // Right Leg
            DrawBone(pelvis3D, rHip3D);
            DrawBone(rHip3D, rKnee3D);
            DrawBone(rKnee3D, rFoot3D);
        }

        // 7. Draw Distance Label
        if (g_ESP.bDistance && distance > 0.0f) {
            char distText[32];
            snprintf(distText, sizeof(distText), "%.0fm", distance);
            ImVec2 textSize = ImGui::CalcTextSize(distText);
            ImVec2 textPos(centerX - (textSize.x / 2.0f), botY + 2.0f);

            // Shadow / Outline for text
            drawList->AddText(ImVec2(textPos.x + 1, textPos.y + 1), ImColor(0, 0, 0, 220), distText);
            drawList->AddText(textPos, ImColor(255, 255, 255, 255), distText);
        }
    }
}

#include <csetjmp>
#include <csignal>
#include <signal.h>
#include <dlfcn.h>

bool Lines;
bool filledbox;
bool espen;
bool gandod;
bool ESP;
bool autofire;
bool INFO;
bool esphpgradient;
bool espweapon;
bool tracer;
int SmoothValue = 5;
bool esptracerglow;
bool espbox;
static int scalern = 0;
bool espfill;
bool espgradient;
bool esphpoutline = true;
bool espdist;
bool addscoreT;
int aimbotfov;
bool HealthEsp;
bool esparm;
int MaterialGlossiness;
float AngleSpeed;
bool antiaims;
bool espname;
bool thirdpers;
bool esphealth;
bool resp;
bool espskeleton;
bool vischeck;
bool espchinahat;
bool skeleton;
bool outoffov;
bool oofvis;
bool ESP3D;
bool watermarkiccuuv;
bool esp3dcorners;
bool visible;
bool doubletap;
static int rectrn = 0;
bool ESPTrail;
float cornered;
float espround;
float espfillp;
bool esp3dcornerstroke;

float visual_circle_size,visual_circle_stroke,visual_lined_size,visual_lined_stroke,visual_esp_line = 1,visual_esp_box = 1,visual_esp_boxth = 1,visual_esp_box_filedth = 1,visual_esp_box_filed = 1,visual_esp_skel = 1;

float espstroke = 2;
float esphpsize = 3;
float width3d = 1.0f;
float oulinewidth3d = 0.5f;
float hatalpha = 0.200f;
float hatradius = 0.50f;
float hatsegments = 10.f;
float esphptextsize = -2;
ImVec4 visibleCol = ImColor(0,255,0);
ImVec4 invisibleCol = ImColor(255,0,0);
bool nightmode;
float nightvalue;static int bonern = 0;
 bool cornerbox;
 bool silentfovglow;
bool Box;

	





struct _Vars {
	bool bESPBox;
	bool bESPEnable;
	bool bESPOutline;
	int bESPRounding;
	bool bESPHealth;
	bool bESPArmor;

   bool bMaterialChams;
ImVec4 cChamsVisible = ImColor(0,255,0);
ImVec4 cChamsInvisible = ImColor(255,0,0);
    ImVec4 bESPColorVisible = {1,1,1,1};
	ImVec4 bESPArmorMax = {0.0864, 0.378, 0.960,1};
	ImVec4 bESPHealthMax = {0.159, 0.960, 0.0864, 1};
	ImVec4 bESPArmorMin = {0.0588, 0.965, 0.980,1.f};
	ImVec4 bESPHealthMin = {0.830, 0.0415, 0.0415, 1};
} Vars;
float lerps(float a, float b, float t) {
	return a + (b - a) * t;
}

ImDrawList* getDrawList(){
	ImDrawList *drawList;
	drawList = ImGui::GetBackgroundDrawList();
	return drawList;
};

void (*AddScore)(void*, int);
void* (*get_camera)();
void* (*get_BipedMap)(void* bone);
Vector3(*get_forward)(void* a);
void (*set_localscale)(void *transform, Vector3 scale);
void* (*get_transform)(void*);
void (*set_position)(void*, Vector3);
bool (*Linecast228)(Vector3,Vector3,int);
int (*GetPlayerTeam)(void*);
int (*GetPlayerHealth)(void *player);
Vector3 (*WorldToViewpoint)(void*, Vector3, int);
Vector3 (*get_position)(void*);
monoString* (*GetNickName)(void*);

void *get_photon(void *player) {
	return *(void **)((uint64_t) player + 0x108);
}

void *get_view(void *player) {
    return *(void **)((uint64_t) player + 0xF8);
}

ImVec2 world2screen_i(Vector3 pos) { 
	auto cam = get_camera();    
	//if (!cam) return {0,0};    

	Vector3 worldPoint = WorldToViewpoint(cam,pos, 2);   
	Vector3 location; 

	int ScreenWidth = ImGui::GetIO().DisplaySize.x; 
	int ScreenHeight = ImGui::GetIO().DisplaySize.y; 

	location.x = ScreenWidth * worldPoint.x; 
	location.y = ScreenHeight - worldPoint.y * ScreenHeight; 
	location.z = worldPoint.z; 


	return {location.x, location.y}; 
} 
ImVec2 world2screen_c(Vector3 pos, bool &checker) { 
	auto cam = get_camera();    
	if (!cam) return {0,0};    
   
	Vector3 worldPoint = WorldToViewpoint(cam,pos, 2);   
	Vector3 location; 
 
	int ScreenWidth = ImGui::GetIO().DisplaySize.x; 
	int ScreenHeight = ImGui::GetIO().DisplaySize.y; 
 
	location.x = ScreenWidth * worldPoint.x; 
	location.y = ScreenHeight - worldPoint.y * ScreenHeight; 
	location.z = worldPoint.z; 
 
	checker = location.z > 1; 
 
	return {location.x, location.y}; 
}




int localTeam;

std::vector<void*> players;

void clearPlayers() {
  if (!players.empty()) {
    std::vector<void*> pls;
    for (int i = 0; i < players.size(); i++) {
	  if (players[i] != NULL && get_photon(players[i]) !=NULL && GetPlayerHealth(get_photon(players[i])) > 0) {
	    pls.push_back(players[i]);
	  }
    }
    players = pls;
  }
}

bool playerFind(void *pl) {
  if (pl != NULL) {
	for (int i = 0; i < players.size(); i++) {
	  if (pl == players[i]) return true;
	}
  }
  return false;
}

void(*old_becameinvisible)(void*);
void becameinvisible(void*a){
}
void(*old_becamevisible)(void*);
void becamevisible(void*a){
	old_becamevisible(a);
}

Vector3 GetPlayerLocation(void *player) {
  Vector3 location;
  location = get_position(get_transform(player));
  return location;
}void *get_body(void *player) {
    return *(void **)((uint64_t) get_BipedMap(player) + 0x28);
}
void *get_head(void *player) {
    return *(void **)((uint64_t) get_BipedMap(player) + 0x18);
}
void *get_neck(void *player) {
    return *(void **)((uint64_t) get_BipedMap(player) + 0x20);
}
void *get_hip(void *player) {
    return *(void **)((uint64_t) get_BipedMap(player) + 0x78);
}


Vector3 GetPlayerBody(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x78));
}

Vector3 GetPlayerHead(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x18));
}
Vector3 GetPlayerNeck(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x20));
}
Vector3 GetPlayerHip(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x78));
}
Vector3 GetPlayerleftLowerArm(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x48));
}
Vector3 GetPlayerLeftHand(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x50));
}
Vector3 GetPlayerRightHand(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x70));
}
Vector3 GetPlayerleftUpperArm(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x40));
}
Vector3 GetPlayerrightLowerArm(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x68));
}
Vector3 GetPlayerrightUpperArm(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x60));
}
Vector3 GetPlayerleftLowerLeg(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x90));
}
Vector3 GetPlayerleftUpperLeg(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0x88));
}
Vector3 GetPlayerrightLowerLeg(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0xA8));
}
Vector3 GetPlayerrightUpperLeg(void *player) {
    return get_position(*(void **) ((uint64_t) get_BipedMap(player) + 0xA0));
}



bool IsPlayerVisible(void* player) {
    if (get_camera()) {
        Vector3 CameraPos         = get_position(get_transform(get_camera()));

        bool CanSeeHead           = !Linecast228(CameraPos,GetPlayerHead          (player),16384);
        bool CanSeeHip            = !Linecast228(CameraPos,GetPlayerHip           (player),16384);
bool CanSeeBody           = !Linecast228(CameraPos,GetPlayerBody          (player),16384);
        bool CanSeeLeftLowerArm   = !Linecast228(CameraPos,GetPlayerleftLowerArm  (player),16384);
        bool CanSeeRightLowerArm  = !Linecast228(CameraPos,GetPlayerrightLowerArm (player),16384);
        bool CanSeeLeftLowerLeg   = !Linecast228(CameraPos,GetPlayerleftLowerLeg  (player),16384);
        bool CanSeeRightLowerLeg  = !Linecast228(CameraPos,GetPlayerrightLowerLeg (player),16384);

        return
        CanSeeHead            ||
        CanSeeHip             ||
        CanSeeBody            ||
        CanSeeLeftLowerArm    ||
        CanSeeRightLowerArm   ||
        CanSeeLeftLowerLeg    ||
        CanSeeRightLowerLeg    ;
    }
    return false;
}
bool IsHeadVisible(void* player) {
    if (get_camera()) {
        Vector3 CameraPos         = get_position(get_transform(get_camera()));

        bool CanSeeHead           = !Linecast228(CameraPos,GetPlayerHead          (player),16384);

        return
        CanSeeHead;            
    }
    return false;
}

bool IsNeckVisible(void* player) {
    if (get_camera()) {
        Vector3 CameraPos         = get_position(get_transform(get_camera()));

        bool CanSeeNeck           = !Linecast228(CameraPos,GetPlayerNeck          (player),16384);

        return
        CanSeeNeck;            
    }
    return false;
}

bool IsBodyVisible(void* player) {
    if (get_camera()) {
        Vector3 CameraPos         = get_position(get_transform(get_camera()));

        bool CanSeeBody           = !Linecast228(CameraPos,GetPlayerBody          (player),16384);

        return
        CanSeeBody;            
    }
    return false;
}

void *aimedPlayer = NULL;
bool enemyscale;
Vector3 flypos;
float xu = 0;
float yu = 0;
void* atu;
float flySpeed = 10;
bool localscale;
bool localGrav;
int scaleX = 1;
int scaleY = 1;
int scaleZ = 1;
bool telekill;
bool godmode;
bool silent;
bool silentfov;
int silentaimfov;
ImVec4 fovcolor = {255,255,255,255};
bool isDead;
bool addscored;

Vector3 coords;

void* (*get_owner)(void*);


const char* bonetype[] = {("Head"),("Neck"),("Body")};	
static int linern = 0;
const char* linetype[] = {("top"),("center"),("bottom")};


void (*old_godmod)(void *instance, int hp, int armor, bool has, bool shield, float godtime);
void godmod(void *instance, int hp, int armor, bool has, bool shield, float godtime) {
        if (godmode) {
   has = true;
   armor = 9999;
   hp = 9999;
   shield = true;
   godtime = 9999.0f;
        } 
    return old_godmod(instance, hp, armor, has, shield, godtime);
}




float (*GetDeltaTime)(void* nul);


void *localPlayer = NULL;





void (*old_Player_Update)(void* player);
void Player_Update(void* player) {    
    if (player) {
        auto PhotonView = get_view(player);
        if (PhotonView) {
            auto owner = get_owner(PhotonView);
            if (owner){
                bool IsLocal = *(bool *) ((uint64_t) owner + 0x28);
                if(Vars.bESPEnable){
                if(GetPlayerHealth(get_photon(player)) > 0){
                    if(!playerFind(player) && !IsLocal) players.push_back(player);
                    clearPlayers();

                }
            }
void* playerInstance = player;
if(IsLocal){
localPlayer = player;

localTeam = GetPlayerTeam(owner);



}}}
if(addscored){
              AddScore(get_photon(localPlayer),10);  
            
            }

    }

    
    old_Player_Update(player);
}


void* (*old_CastBullet)(Vector3 startPosition, Vector3 direction,  void* parameters); 
void* CastBullet(Vector3 startPosition, Vector3 direction,  void* parameters) { 



if (aimedPlayer && silent && get_photon(aimedPlayer)) {
		if (GetPlayerHealth(get_photon(aimedPlayer)) > 0 && get_BipedMap(aimedPlayer)) {
			if(aimedPlayer){
		        void *aimedPlayerHead= *(void * *)((uint64_t)get_BipedMap(aimedPlayer) + 0x18); 
                void *aimedPlayerNeck = *(void * *) ((uint64_t) get_BipedMap(aimedPlayer) + 0x20); 
                void *aimedPlayerBody = *(void * *) ((uint64_t) get_BipedMap(aimedPlayer) + 0x30); 
		          	if (aimedPlayerHead && bonern == 0) { 
		            	Vector3 target = get_position(aimedPlayerHead) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
if(vischeck && IsHeadVisible(aimedPlayer)){

		                	direction = Vector3::Normalized(get_position(aimedPlayerHead) - startPosition); 
		              	} 

if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerHead) - startPosition); 
}
}
		          	}
                   if (aimedPlayerNeck && bonern == 1) { 
		            	Vector3 target = get_position(aimedPlayerNeck) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 

if(vischeck && IsNeckVisible(aimedPlayer)){

		                	direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition); 
		              	} 
if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition); 
}
}

		          	}
                    if (aimedPlayerBody && bonern == 2) { 
		            	Vector3 target = get_position(aimedPlayerBody) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
if(vischeck && IsBodyVisible(aimedPlayer)){
		                	direction = Vector3::Normalized(get_position(aimedPlayerBody) - startPosition); 
		              	}
if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition);
}

} 
		          	}
		        
				
		    }
		} 
    } 

 	
 	return old_CastBullet(startPosition, direction, parameters); 
} 
void* (*old_CastBullet1)(Vector3 startPosition, Vector3 direction,  void* parameters); 
void* CastBullet1(Vector3 startPosition, Vector3 direction,  void* parameters) { 



if (aimedPlayer && silent && get_photon(aimedPlayer)) {
		if (GetPlayerHealth(get_photon(aimedPlayer)) > 0 && get_BipedMap(aimedPlayer)) {
			if(aimedPlayer){
		        void *aimedPlayerHead= *(void * *)((uint64_t)get_BipedMap(aimedPlayer) + 0x18); 
                void *aimedPlayerNeck = *(void * *) ((uint64_t) get_BipedMap(aimedPlayer) + 0x20); 
                void *aimedPlayerBody = *(void * *) ((uint64_t) get_BipedMap(aimedPlayer) + 0x30); 
		          	if (aimedPlayerHead && bonern == 0) { 
		            	Vector3 target = get_position(aimedPlayerHead) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
if(vischeck && IsHeadVisible(aimedPlayer)){

		                	direction = Vector3::Normalized(get_position(aimedPlayerHead) - startPosition); 
		              	} 

if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerHead) - startPosition); 
}
}
		          	}
                   if (aimedPlayerNeck && bonern == 1) { 
		            	Vector3 target = get_position(aimedPlayerNeck) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 

if(vischeck && IsNeckVisible(aimedPlayer)){

		                	direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition); 
		              	} 
if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition); 
}
}

		          	}
                    if (aimedPlayerBody && bonern == 2) { 
		            	Vector3 target = get_position(aimedPlayerBody) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
if(vischeck && IsBodyVisible(aimedPlayer)){
		                	direction = Vector3::Normalized(get_position(aimedPlayerBody) - startPosition); 
		              	}
if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition);
}

} 
		          	}
		        
				
		    }
		} 
    } 

 	
 	return old_CastBullet1(startPosition, direction, parameters); 
} 
void* (*old_CastBullet2)(Vector3 startPosition, Vector3 direction,  void* parameters); 
void* CastBullet2(Vector3 startPosition, Vector3 direction,  void* parameters) { 



if (aimedPlayer && silent && get_photon(aimedPlayer)) {
		if (GetPlayerHealth(get_photon(aimedPlayer)) > 0 && get_BipedMap(aimedPlayer)) {
			if(aimedPlayer){
		        void *aimedPlayerHead= *(void * *)((uint64_t)get_BipedMap(aimedPlayer) + 0x18); 
                void *aimedPlayerNeck = *(void * *) ((uint64_t) get_BipedMap(aimedPlayer) + 0x20); 
                void *aimedPlayerBody = *(void * *) ((uint64_t) get_BipedMap(aimedPlayer) + 0x30); 
		          	if (aimedPlayerHead && bonern == 0) { 
		            	Vector3 target = get_position(aimedPlayerHead) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
if(vischeck && IsHeadVisible(aimedPlayer)){

		                	direction = Vector3::Normalized(get_position(aimedPlayerHead) - startPosition); 
		              	} 

if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerHead) - startPosition); 
}
}
		          	}
                   if (aimedPlayerNeck && bonern == 1) { 
		            	Vector3 target = get_position(aimedPlayerNeck) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 

if(vischeck && IsNeckVisible(aimedPlayer)){

		                	direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition); 
		              	} 
if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition); 
}
}

		          	}
                    if (aimedPlayerBody && bonern == 2) { 
		            	Vector3 target = get_position(aimedPlayerBody) - get_position(get_transform(get_camera())); 
		            	float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
		            	if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
if(vischeck && IsBodyVisible(aimedPlayer)){
		                	direction = Vector3::Normalized(get_position(aimedPlayerBody) - startPosition); 
		              	}
if(!vischeck){
direction = Vector3::Normalized(get_position(aimedPlayerNeck) - startPosition);
}

} 
		          	}
		        
				
		    }
		} 
    } 

 	
 	return old_CastBullet2(startPosition, direction, parameters); 
} 





#import "Helper/Functions/Esp.h"

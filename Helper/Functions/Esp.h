#include <cstring>


#define ScreenWidth  [UIScreen mainScreen].bounds.size.width
#define ScreenHeight [UIScreen mainScreen].bounds.size.height

void *get_boneget(void *player, uint64_t premit) {
  return *(void **)((uint64_t) get_BipedMap(player) + premit);
}
template <typename T>
inline T clamp(const T& n, const T& lower, const T& upper) {
  return std::max(lower, std::min(n, upper));
}

inline float lerp(float a, float b, float f) {
	return clamp<float>(a + f * (b - a),a > b ? b : a,a > b ? a : b);
}

ImVec2 calcTextSize(std::string text, double scaling) {
  return ImGui::CalcTextSize(text.c_str());
}

inline ImColor collerp(ImColor a, ImColor b, float f) {
  return {a.Value.x + f * (b.Value.x - a.Value.x), a.Value.y + f * (b.Value.y - a.Value.y), a.Value.z + f * (b.Value.z - a.Value.z), a.Value.w + f * (b.Value.w - a.Value.w)};

}






void AddText(bool shadow, bool outline, const ImVec2& pos, ImColor color, const char* value, ImDrawList* drawlist = ImGui::GetBackgroundDrawList()) {
        const static std::vector<ImVec2> text_offsets {
                {1*ImGui::GetIO().FontGlobalScale, 1*ImGui::GetIO().FontGlobalScale},
                {-1*ImGui::GetIO().FontGlobalScale, -1*ImGui::GetIO().FontGlobalScale},
                {0, 1*ImGui::GetIO().FontGlobalScale},
                {0, -1*ImGui::GetIO().FontGlobalScale},
                {1*ImGui::GetIO().FontGlobalScale, 1*ImGui::GetIO().FontGlobalScale},
                {-1*ImGui::GetIO().FontGlobalScale, -1*ImGui::GetIO().FontGlobalScale},
                {-1*ImGui::GetIO().FontGlobalScale, 1*ImGui::GetIO().FontGlobalScale},
                {1*ImGui::GetIO().FontGlobalScale, -1*ImGui::GetIO().FontGlobalScale},
                {1*ImGui::GetIO().FontGlobalScale, 0},
                {-1*ImGui::GetIO().FontGlobalScale, 0},
                {0, 1*ImGui::GetIO().FontGlobalScale},
                {0, -1*ImGui::GetIO().FontGlobalScale}
        };
        if (outline) {
            for (auto text_offset: text_offsets) {
                drawlist->AddText({pos.x+text_offset.x, pos.y+text_offset.y}, ImColor(0, 0, 0, (int)float(color.Value.w * 255)), value);
            }
        }
        if (shadow) drawlist->AddText({ pos.x + 2, pos.y + 2 }, ImColor(5, 5, 5, (int)float(color.Value.w * 255)), value);
        drawlist->AddText(pos, color, value);
}
void SilentPos(void* player, ImColor color){
void *aimedPlayerHead = *(void **) ((uint64_t) get_BipedMap(player) + 0x18);
Vector3 HeadPos = Vector3(get_position(aimedPlayerHead));
ImGui::GetBackgroundDrawList()->AddCircle(ImVec2(HeadPos.x, HeadPos.y), 10, ImGui::ColorConvertFloat4ToU32(color), 100,1);
}








void DrawEsp() {


    bool checker1;
    bool checker2;
    


  if (Vars.bESPEnable) {
    getDrawList()->AddText({20,20}, ImColor(255,255,255), std::to_string(players.size()).c_str());clearPlayers();

    
    for (int i = 0; i < players.size(); i++) {


      if (players[i] && GetPlayerTeam(get_photon(players[i])) != localTeam) {

        
        void *player = players[i];
        auto health = GetPlayerHealth(get_photon(player));
        
        auto pos = get_position(get_transform(player));

auto w2sTop = world2screen_i(pos + Vector3(0, 2, 0));




auto pname = GetNickName(get_photon(player));
								std::string names = "null";
								if (pname) names = pname->toCPPString();
								std::transform(names.begin(), names.end(), names.begin(), ::tolower);
								auto playername = names;
								std::string name = names;

							auto healthL = (float) health;
								const auto hayasaka =
												(clamp<float>(healthL, 25, 75) - 25.f) / 50.f;
        float health_multiplier = (float) health / 100.f;
								auto hpcolor = ImColor(int(120 + 135 * (1 - hayasaka)),
																			 int(50.f + 175.f * hayasaka), int(80));

								auto minhpcolor = ImColor(int(120 + 135 * (1 - 0)),
																					int(50.f + 175.f * 0), int(80));

								NSString *healthString = [NSString stringWithFormat:@"%d", health];
								const char *healthCString = [healthString UTF8String];
          

								if (healthL > 100) {
										hpcolor = ImColor(156,43,166,90);
										minhpcolor = ImColor(156,43,166,90);
								}
								healthL = clamp<float>(healthL, 0, 100);



         
   
       
         

				
        Vector3 viewpos = get_position(get_transform(get_camera()));
        bool ray = IsPlayerVisible(player);
static float animationTime = 0.0f; 
static float animationSpeed = 0.5f; 
     
             
            
   


        auto w2sCheck = false;
                
        ImVec2 top_pos(
          world2screen_i(pos + Vector3(0, 1.9f, 0))
        );

        ImVec2 bot_pos(
          world2screen_i(pos + Vector3(0, -0.15f, 0))
        );
                            
        auto pmtXtop = top_pos.x;
        auto pmtXbottom = bot_pos.x;
        if (top_pos.x > bot_pos.x) {
          pmtXtop = bot_pos.x;
          pmtXbottom = top_pos.x;
        }

        world2screen_c(pos + Vector3(0, 0.75f, 0), w2sCheck);

                    
        float positionCalc = fabs((top_pos.y - bot_pos.y) * (0.0092f / 0.019f) / 2);
 
        ImRect rect(
          ImVec2(pmtXtop - positionCalc, top_pos.y),
          ImVec2(pmtXbottom + positionCalc, bot_pos.y)
        );

        int distance_scaling = 1;

    
       
        auto color = ray ? visibleCol : invisibleCol;

        if (w2sCheck) {
          
          
      if (Box) {
    if (Vars.bESPOutline) 
        getDrawList()->AddRect(rect.Min, rect.Max, ImColor(0, 0, 0), Vars.bESPRounding, 0, 3);
    
    getDrawList()->AddRect(rect.Min, rect.Max, ImColor(color), Vars.bESPRounding, 0, 1);

    ImVec2 textPos = ImVec2(rect.Min.x - 10, rect.Max.y + 5); 

    getDrawList()->AddText(textPos, ImColor(255, 255, 255), "t.me@brutaltrip");

}
    
if (filledbox) {
    animationTime += ImGui::GetIO().DeltaTime * (animationSpeed * 0.75f); 


    ImVec4 color1 = ImVec4(color.x, color.y, color.z, 0.1f);
    ImVec4 color2 = ImVec4(color.x + 0.1f, color.y + 0.1f, color.z + 0.1f, 0.2f); 


    float alpha = 0.1f + 0.2f * (sin(animationTime * 1.5f) + 1) / 2; 
    static float currentAlpha1 = color1.w; 
    static float currentAlpha2 = color2.w; 
    currentAlpha1 += (alpha - currentAlpha1) * 0.1f; 
    currentAlpha2 += (alpha - currentAlpha2) * 0.1f;


    getDrawList()->AddRectFilled(rect.Min, rect.Max, ImColor(color1.x, color1.y, color1.z, currentAlpha1), Vars.bESPRounding, 0);
    getDrawList()->AddRectFilled(rect.Min, rect.Max, ImColor(color2.x, color2.y, color2.z, currentAlpha2), Vars.bESPRounding, 0);

    ImVec2 textPos = ImVec2(rect.Min.x - 10, rect.Max.y + 5); 




    getDrawList()->AddText(textPos, ImColor(255, 255, 255), "t.me@brutaltrip");

}
  if (cornerbox) {
    float cornerSize = 7.0f; 
    ImVec2 topLeft = rect.Min;
    ImVec2 topRight = ImVec2(rect.Max.x, rect.Min.y);
    ImVec2 bottomLeft = ImVec2(rect.Min.x, rect.Max.y);
    ImVec2 bottomRight = rect.Max;


    getDrawList()->AddLine(topLeft, ImVec2(topLeft.x + cornerSize, topLeft.y), ImColor(color), 1.0f);
    getDrawList()->AddLine(topLeft, ImVec2(topLeft.x, topLeft.y + cornerSize), ImColor(color), 1.0f);

  
    getDrawList()->AddLine(topRight, ImVec2(topRight.x - cornerSize, topRight.y), ImColor(color), 1.0f);
    getDrawList()->AddLine(topRight, ImVec2(topRight.x, topRight.y + cornerSize), ImColor(color), 1.0f);


    getDrawList()->AddLine(bottomLeft, ImVec2(bottomLeft.x + cornerSize, bottomLeft.y), ImColor(color), 1.0f);
    getDrawList()->AddLine(bottomLeft, ImVec2(bottomLeft.x, bottomLeft.y - cornerSize), ImColor(color), 1.0f);


    getDrawList()->AddLine(bottomRight, ImVec2(bottomRight.x - cornerSize, bottomRight.y), ImColor(color), 1.0f);
    getDrawList()->AddLine(bottomRight, ImVec2(bottomRight.x, bottomRight.y - cornerSize), ImColor(color), 1.0f);

    ImVec2 textPos = ImVec2(rect.Min.x - 10, rect.Max.y + 5);


    getDrawList()->AddText(textPos, ImColor(255, 255, 255), "t.me@brutaltrip");

}
}

if (INFO) {
    float textOffsetX = 5.0f; 
    float textOffsetY = 0.0f;  
    ImColor textColor = ImColor(255, 255, 255); 
    ImColor outlineColor = ImColor(0, 0, 0); 
    float outlineOffset = 1.0f; 

    auto addTextWithOutline = [&](const char* text, float offsetY) {
        getDrawList()->AddText(ImVec2(rect.Max.x + textOffsetX + outlineOffset, rect.Min.y + offsetY + outlineOffset), outlineColor, text);
        getDrawList()->AddText(ImVec2(rect.Max.x + textOffsetX - outlineOffset, rect.Min.y + offsetY + outlineOffset), outlineColor, text);
        getDrawList()->AddText(ImVec2(rect.Max.x + textOffsetX + outlineOffset, rect.Min.y + offsetY - outlineOffset), outlineColor, text);
        getDrawList()->AddText(ImVec2(rect.Max.x + textOffsetX - outlineOffset, rect.Min.y + offsetY - outlineOffset), outlineColor, text);
        
        getDrawList()->AddText(ImVec2(rect.Max.x + textOffsetX, rect.Min.y + offsetY), textColor, text);

    };


    ImFont* originalFont = ImGui::GetFont();
    


    ImFont* smallerFont = ImGui::GetIO().Fonts->Fonts[0]; 
    ImGui::PushFont(smallerFont); 

    addTextWithOutline("HK", textOffsetY);
    textOffsetY += 15.0f; 
    addTextWithOutline("IOS", textOffsetY);
    textOffsetY += 15.0f;
    addTextWithOutline("RUN", textOffsetY);

    ImGui::PopFont(); 

    ImVec2 textPos = ImVec2(rect.Min.x - 10, rect.Max.y + 5); 


    getDrawList()->AddText(textPos, ImColor(255, 255, 255), "t.me@brutaltrip");

}

if (HealthEsp) {
    const char* playerName = "Player"; 
    ImVec2 text_size = ImGui::CalcTextSize(playerName); 
    ImVec2 name_pos = {
        rect.Min.x + (rect.GetWidth() / 2) - text_size.x / 2,
        rect.Min.y - 2 - text_size.y - 5
    };


    ImFont* smallFont = ImGui::GetIO().Fonts->AddFontFromFileTTF("PIRVET.ttf", 9.0f); 

    ImVec2 background_pos_thick = {name_pos.x - 5, name_pos.y - 3};
    ImVec2 background_size_thick = {text_size.x + 10, text_size.y + 6};
    getDrawList()->AddRectFilled(background_pos_thick, ImVec2(background_pos_thick.x + background_size_thick.x, background_pos_thick.y + background_size_thick.y), ImColor(0, 0, 0, 150), 2);


ImVec2 line_start = {background_pos_thick.x, background_pos_thick.y + background_size_thick.y - 1};
float line_end_x = background_pos_thick.x + background_size_thick.x * health_multiplier;
ImVec2 line_end = {line_end_x, background_pos_thick.y + background_size_thick.y - 1};


getDrawList()->AddLine(line_start, line_end, ImColor(50, 205, 50, 100), 6); 
getDrawList()->AddLine(line_start, line_end, ImColor(50, 205, 50), 2); 


    float circle_radius = 15.0f; 
    ImVec2 circle_pos = {background_pos_thick.x - circle_radius - 5, name_pos.y}; 
getDrawList()->AddCircle(circle_pos, circle_radius, ImColor(255, 255, 255)); 


ImGui::PushFont(smallFont);
ImVec2 text_circle_size = ImGui::CalcTextSize("p"); 
ImVec2 text_circle_pos = {
    circle_pos.x - text_circle_size.x / 2,
    circle_pos.y - text_circle_size.y / 2
};
AddText(true, false, text_circle_pos, ImGui::ColorConvertFloat4ToU32(ImColor(0, 0, 0)), "p"); 
ImGui::PopFont();
   
    ImVec2 textPos = ImVec2(rect.Min.x - 10, rect.Max.y + 5); 


    getDrawList()->AddText(textPos, ImColor(255, 255, 255), "t.me@brutaltrip");



if(silent && get_BipedMap(player)){ 
		        void *aimedPlayerHead = *(void * *) ((uint64_t) get_BipedMap(player) + 0x18); 
                void *aimedPlayerNeck = *(void * *) ((uint64_t) get_BipedMap(player) + 0x20); 
                void *aimedPlayerBody = *(void * *) ((uint64_t) get_BipedMap(player) + 0x30); 
if (aimedPlayerHead && bonern == 0) { 
                  Vector3 target = get_position(aimedPlayerHead) - get_position(get_transform(get_camera())); 
                  float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
                  if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
                        
                                    aimedPlayer = player;
                                    
		                
                    }   
                }
if (aimedPlayerNeck && bonern == 1) { 
                  Vector3 target = get_position(aimedPlayerNeck) - get_position(get_transform(get_camera())); 
                  float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
                  if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
                                            
                                    aimedPlayer = player;
                                    

		                
                    } 
                }
if (aimedPlayerBody && bonern == 2) { 
                  Vector3 target = get_position(aimedPlayerBody) - get_position(get_transform(get_camera())); 
                  float aimAngle = Vector3::Angle(target, get_forward(get_transform(get_camera())) * 100); 
                  if (aimAngle <= float(silentaimfov) / 700.0f && target != Vector3(0,0,0)) { 
                                                
                           
                                aimedPlayer = player;
                                    
		                
                    } 
                }
}



          


if (Lines) {


    if (linern == 0) {

        ImGui::GetBackgroundDrawList()->AddLine(
            {ImGui::GetIO().DisplaySize.x / 2, 0}, 
            {rect.GetCenter().x, rect.Min.y}, 
            ImColor(color.x * 255, color.y * 255, color.z * 255, color.w * 255));
    }
    
    if (linern == 1) {
        ImGui::GetBackgroundDrawList()->AddLine(
            {ImGui::GetIO().DisplaySize.x / 2, ImGui::GetIO().DisplaySize.y / 2}, 
            {rect.GetCenter().x, rect.Min.y}, 
            ImColor(color.x * 255, color.y * 255, color.z * 255, color.w * 255));
    }

    if (linern == 2) {
        ImGui::GetBackgroundDrawList()->AddLine(
            {ImGui::GetIO().DisplaySize.x / 2, ImGui::GetIO().DisplaySize.y}, 
            {rect.GetCenter().x, rect.Max.y}, 
            ImColor(color.x * 255, color.y * 255, color.z * 255, color.w * 255));

    ImVec2 textPos = ImVec2(rect.Min.x - 10, rect.Max.y + 5); 


    getDrawList()->AddText(textPos, ImColor(255, 255, 255), "t.me@brutaltrip");

    }
}

if (espname) {

    ImVec2 textSize = ImGui::CalcTextSize(name.c_str());
    ImVec2 textPos = ImVec2(rect.Min.x + (textSize.x / 2) + 5, rect.Min.y);


    ImColor glowColor(255, 255, 0, 100); 
    ImColor outlineColor(0, 0, 0);
    ImColor textColor(255, 255, 255); 


    for (int xOffset = -1; xOffset <= 1; xOffset++) {
        for (int yOffset = -1; yOffset <= 1; yOffset++) {
            if (xOffset != 0 || yOffset != 0) { 
                ImVec2 offset(static_cast<float>(xOffset), static_cast<float>(yOffset));
                getDrawList()->AddText(ImGui::GetFont(), 12, textPos, outlineColor, name.c_str());
            }
        }
    }


    getDrawList()->AddText(ImGui::GetFont(), 12, textPos, glowColor, name.c_str());


    getDrawList()->AddText(ImGui::GetFont(), 12, textPos, textColor, name.c_str());
}

}
}
if (silentfov) { ImGui::GetBackgroundDrawList()->AddCircle(ImVec2(ImGui::GetIO().DisplaySize.x / 2, ImGui::GetIO().DisplaySize.y / 2), silentaimfov - 45, ImGui::ColorConvertFloat4ToU32(fovcolor), 100,0.5); }



    }
  }
}
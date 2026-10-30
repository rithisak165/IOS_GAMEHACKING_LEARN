float toasttimer = 0;
float toastmaxtime = 0;
const char* toasttext = 0;

void RenderToast() {
    if (toasttimer <= 0) return;
    toasttimer -= ImGui::GetIO().DeltaTime;
    float alpha;
    if (toasttimer >= 0.1f && toasttimer <= toastmaxtime - 0.1f) alpha = 1;
    if (toasttimer < 0.1f) alpha = toasttimer * 10;
    if (toasttimer > toastmaxtime - 0.1f) alpha = (toastmaxtime - toasttimer) * 10;

    ImGui::GetForegroundDrawList()->AddRectFilled(ImVec2(ImGui::GetIO().DisplaySize.x / 2 - ImGui::CalcTextSize(toasttext).x/2 - 20, ImGui::GetIO().DisplaySize.y * 0.8 - ImGui::CalcTextSize(toasttext).y/2 - 20 - alpha * 5),
                                            ImVec2(ImGui::GetIO().DisplaySize.x / 2 + ImGui::CalcTextSize(toasttext).x/2 + 20, ImGui::GetIO().DisplaySize.y * 0.8 + ImGui::CalcTextSize(toasttext).y/2 + 20 - alpha * 5),
                                            ImColor(0.1f,0.1f,0.1f,alpha), 5.0f);

    ImGui::GetForegroundDrawList()->AddText(ImVec2(ImGui::GetIO().DisplaySize.x / 2 - ImGui::CalcTextSize(toasttext).x/2, ImGui::GetIO().DisplaySize.y * 0.8 - ImGui::CalcTextSize(toasttext).y/2 - alpha * 5),
                                                  ImColor(1.0f,1.0f,1.0f,alpha), toasttext);
}

void Toast(const char *text, int length = 1) {
    toasttext = text;
    toasttimer = length;
    toastmaxtime = length;
}

Handle g_hSavedSetupCookie;

public void OnPluginStart_Cookies() {
    g_hSavedSetupCookie = RegClientCookie("zmarket_savedsetup", "Saved Weapon Setup", CookieAccess_Private);
    if (g_hSavedSetupCookie == INVALID_HANDLE) {
        LogError("Failed to register zmarket_savedsetup cookie!");
    } else {
        LogMessage("zmarket_savedsetup cookie registered successfully!");
    }
}

void GetClientSetupCookie(int client, char[] setup, int maxlen) {
    if (g_hSavedSetupCookie == INVALID_HANDLE) {
        LogError("Attempted to get cookie, but g_hSavedSetupCookie is INVALID_HANDLE");
        strcopy(setup, maxlen, "");
        return;
    }
    GetClientCookie(client, g_hSavedSetupCookie, setup, maxlen);
}

void ClearClientSetup(int client) {
    SetClientCookie(client, g_hSavedSetupCookie, "");
}
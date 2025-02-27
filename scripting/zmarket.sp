#include <sourcemod>
#include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <multicolors>
#include "weapondata.inc"
#include "zmarketcookies.inc"
#include <zriot>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name = "ZMarket",
    author = "+SyntX",
    description = "A weapon market plugin for CS:S",
    version = "1.0",
    url = ""
};

ConVar g_cvBuyZoneOnly;
ConVar g_cvAllowSMCommand;
ConVar g_cvPriceMultiplier;

Handle g_hAutoRebuyCookie;
bool g_bAutoRebuy[MAXPLAYERS + 1];

public void OnPluginStart() {
    g_cvBuyZoneOnly = CreateConVar("sm_zmarket_buyzone_only", "0", "Restrict weapon purchases to buy zones. 1 = Enabled, 0 = Disabled");
    g_cvAllowSMCommand = CreateConVar("sm_zmarket_allow_sm_command", "1", "Allow buying weapons via commands like !ak47. 1 = Enabled, 0 = Disabled");
    g_cvPriceMultiplier = CreateConVar("sm_zmarket_price_multiplier", "1.5", "Price multiplier for buying weapons outside buy zones.");

    RegConsoleCmd("sm_zmarket", Command_ZMarket, "Opens the ZMarket menu");

    g_WeaponData = new ArrayList(sizeof(WeaponData));
    LoadWeaponData();

    // Cookies
    g_hAutoRebuyCookie = RegClientCookie("zmarket_autorebuy", "Auto-Rebuy Toggle", CookieAccess_Private);
    SetCookieMenuItem(AutoRebuyCookieHandler, 0, "Auto-Rebuy");

    for (int i = 1; i <= MaxClients; i++) {
        if (AreClientCookiesCached(i)) {
            OnClientCookiesCached(i);
        }
    }

    OnPluginStart_Cookies();
    HookEvent("player_spawn", Event_PlayerSpawn);

    AutoExecConfig(true);
}

public void OnClientPutInServer(int client) {
    if (g_bAutoRebuy[client]) {
        BuySavedSetup(client);
    }
}

public void OnRoundStart() {
    CreateTimer(0.5, Timer_GiveSavedWeapons, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_GiveSavedWeapons(Handle timer, any client) {
    if (IsClientInGame(client) && IsPlayerAlive(client) && g_bAutoRebuy[client]) {
        BuySavedSetup(client);
    }
    return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && IsClientInGame(client) && IsPlayerAlive(client) && g_bAutoRebuy[client]) {
        CreateTimer(0.1, Timer_GiveSavedWeapons, client, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientCookiesCached(int client) {
    char sValue[8];
    GetClientCookie(client, g_hAutoRebuyCookie, sValue, sizeof(sValue));
    g_bAutoRebuy[client] = (sValue[0] != '\0' && StringToInt(sValue) == 1);
}

public void AutoRebuyCookieHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlen) {
    if (action == CookieMenuAction_DisplayOption) {
        Format(buffer, maxlen, "Auto-Rebuy: %s", g_bAutoRebuy[client] ? "Yes" : "No");
    } else if (action == CookieMenuAction_SelectOption) {
        ToggleAutoRebuy(client);
        ShowCookieMenu(client);
    }
}

public Action Command_BuyWeaponDirect(int client, int args) {
    if (!IsValidClient(client) || !IsPlayerAlive(client)) {
        PrintToChat(client, "[\x04ZMarket\x01] You must be alive to buy weapons.");
        return Plugin_Handled;
    }

    if (ZRiot_IsClientZombie(client)) {
        PrintToChat(client, "[\x04ZMarket\x01] Zombies cannot use the weapon market.");
        return Plugin_Handled;
    }

    if (GetConVarInt(g_cvAllowSMCommand) != 1 || GetConVarInt(g_cvBuyZoneOnly) == 1) {
        PrintToChat(client, "[\x04ZMarket\x01] Buying weapons via commands is disabled.");
        return Plugin_Handled;
    }

    char command[32];
    GetCmdArg(0, command, sizeof(command));

    int weaponIndex = FindWeaponByCommand(command);
    if (weaponIndex == -1) {
        PrintToChat(client, "[\x04ZMarket\x01] Invalid weapon command.");
        return Plugin_Handled;
    }

    WeaponData weapon;
    g_WeaponData.GetArray(weaponIndex, weapon);

    if (weapon.Restricted) {
        PrintToChat(client, "[\x04ZMarket\x01] %s is restricted and cannot be purchased.", weapon.DisplayName);
        return Plugin_Handled;
    }

    int finalPrice = IsPlayerInBuyZone(client) ? weapon.Price : RoundToNearest(weapon.Price * GetConVarFloat(g_cvPriceMultiplier));
    if (GetClientMoney(client) < finalPrice) {
        PrintToChat(client, "[\x04ZMarket\x01] You don't have enough money to buy %s. (Price: $%d)", weapon.DisplayName, finalPrice);
        return Plugin_Handled;
    }

    int currentWeapon = GetPlayerWeaponByEntityName(client, weapon.WeaponEntity);
    if (currentWeapon != -1) {
        BuyAmmoForWeapon(client, weapon);
        return Plugin_Handled;
    }

    int slot = GetWeaponSlot(weapon.WeaponEntity);
    if (slot == -1) {
        PrintToChat(client, "[\x04ZMarket\x01] Unable to determine weapon slot for %s.", weapon.DisplayName);
        return Plugin_Handled;
    }

    int currentWeaponInSlot = GetPlayerWeaponSlot(client, slot);
    if (currentWeaponInSlot != -1) {
        CS_DropWeapon(client, currentWeaponInSlot, false, true);
    }

    GivePlayerItem(client, weapon.WeaponEntity);
    SetClientMoney(client, GetClientMoney(client) - finalPrice);
    PrintToChat(client, "[\x04ZMarket\x01] You have purchased %s for $%d.", weapon.DisplayName, finalPrice);

    return Plugin_Handled;
}

void BuyAmmoForWeapon(int client, WeaponData weapon) {
    char ammoType[32];
    weapon.kvData.GetString("ammotype", ammoType, sizeof(ammoType));

    int ammoIndex = GetAmmoIndex(ammoType);
    if (ammoIndex == -1 || weapon.AmmoPrice <= 0) {
        PrintToChat(client, "[\x04ZMarket\x01] No valid ammo type found for %s.", weapon.DisplayName);
        return;
    }

    if (GetClientMoney(client) < weapon.AmmoPrice) {
        PrintToChat(client, "[\x04ZMarket\x01] You don't have enough money to buy ammo for %s. (Price: $%d)", weapon.DisplayName, weapon.AmmoPrice);
        return;
    }

    ZRiot_GivePlayerAmmo(client, ammoIndex, 1);
    SetClientMoney(client, GetClientMoney(client) - weapon.AmmoPrice);
    PrintToChat(client, "[\x04ZMarket\x01] You have purchased ammo for %s for $%d.", weapon.DisplayName, weapon.AmmoPrice);
}

int GetAmmoIndex(const char[] ammoType) {
    if (StrEqual(ammoType, "ammo_9mm", false)) return 1;
    if (StrEqual(ammoType, "ammo_45acp", false)) return 2;
    if (StrEqual(ammoType, "ammo_50ae", false)) return 3;
    if (StrEqual(ammoType, "ammo_357sig", false)) return 4;
    if (StrEqual(ammoType, "ammo_57mm", false)) return 5;
    if (StrEqual(ammoType, "ammo_556mm", false)) return 6;
    if (StrEqual(ammoType, "ammo_762mm", false)) return 7;
    if (StrEqual(ammoType, "ammo_338magnum", false)) return 8;
    if (StrEqual(ammoType, "ammo_buckshot", false)) return 9;
    if (StrEqual(ammoType, "ammo_308win", false)) return 10;
    if (StrEqual(ammoType, "ammo_357magnum", false)) return 11;
    if (StrEqual(ammoType, "ammo_12gauge", false)) return 12;
    if (StrEqual(ammoType, "ammo_556mm_box", false)) return 13;
    return -1;
}


int FindWeaponByCommand(const char[] command) {
    for (int i = 0; i < g_WeaponData.Length; i++) {
        WeaponData weapon;
        g_WeaponData.GetArray(i, weapon);

        if (strlen(weapon.BuyCommands) == 0) {
            PrintToServer("[ERROR] Weapon '%s' has no buy commands set!", weapon.WeaponName);
            continue;
        }

        char commands[32][32];
        int count = ExplodeString(weapon.BuyCommands, ",", commands, sizeof(commands), sizeof(commands[]));

        for (int j = 0; j < count; j++) {
            TrimString(commands[j]);
            PrintToServer("[DEBUG] Checking command: '%s' against input: '%s'", commands[j], command);

            if (StrEqual(command, commands[j], false)) {
                return i;
            }
        }
    }
    return -1;
}

int GetPlayerWeaponByEntityName(int client, const char[] weaponEntity) {
    for (int i = 0; i < 5; i++) {
        int weapon = GetPlayerWeaponSlot(client, i);
        if (weapon != -1) {
            char classname[32];
            GetEntityClassname(weapon, classname, sizeof(classname));
            if (StrEqual(classname, weaponEntity, false)) {
                return weapon;
            }
        }
    }
    return -1;
}

int GetWeaponSlot(const char[] weaponEntity) {
    for (int i = 0; i < g_WeaponData.Length; i++) {
        WeaponData weapon;
        g_WeaponData.GetArray(i, weapon);
        
        if (StrEqual(weapon.WeaponEntity, weaponEntity, false)) {
            return weapon.Slot;
        }
    }
    return -1;
}


public Action Command_ZMarket(int client, int args) {
    if (!IsValidClient(client)) return Plugin_Handled;

    ShowZMarketMenu(client);
    return Plugin_Handled;
}

void ShowZMarketMenu(int client) {
    Menu menu = new Menu(ZMarketMenuHandler);
    menu.SetTitle("ZMarket Menu");

    char rebuyText[32];
    Format(rebuyText, sizeof(rebuyText), "4. Auto-Rebuy: [%s]", g_bAutoRebuy[client] ? "Yes" : "No");

    menu.AddItem("save", "1. Save Current Setup");
    menu.AddItem("view", "2. View Saved Setup");
    menu.AddItem("buy", "3. Buy Saved Setup");
    menu.AddItem("autorebuy", rebuyText);
    menu.AddItem("buyweapons", "5. Buy Weapons");

    menu.Display(client, MENU_TIME_FOREVER);
}

public int ZMarketMenuHandler(Menu menu, MenuAction action, int client, int param2) {
    if (action == MenuAction_Select) {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "save")) {
            SaveClientSetup(client);
        } else if (StrEqual(info, "view")) {
            ShowViewSavedSetupMenu(client);
        } else if (StrEqual(info, "buy")) {
            BuySavedSetup(client);
        } else if (StrEqual(info, "autorebuy")) {
            ToggleAutoRebuy(client);
            ShowZMarketMenu(client);
        } else if (StrEqual(info, "buyweapons")) {
            ShowBuyWeaponsMenu(client);
        }
    } else if (action == MenuAction_End) {
        delete menu;
    }
    return 0;
}

void SaveClientSetup(int client) {
    char setup[256];
    char primary[32], secondary[32], grenade[32];

    int weapon = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
    if (weapon != -1) GetEntityClassname(weapon, primary, sizeof(primary));

    weapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
    if (weapon != -1) GetEntityClassname(weapon, secondary, sizeof(secondary));

    weapon = GetPlayerWeaponSlot(client, CS_SLOT_GRENADE);
    if (weapon != -1) GetEntityClassname(weapon, grenade, sizeof(grenade));

    Format(setup, sizeof(setup), "%s;%s;%s;weapon_knife", primary, secondary, grenade);
    SetClientCookie(client, g_hSavedSetupCookie, setup);
    PrintToChat(client, "[\x04ZMarket\x01] Your setup has been saved.");
}

void ShowViewSavedSetupMenu(int client) {
    Menu menu = new Menu(ViewSavedSetupMenuHandler);
    menu.SetTitle("View Saved Setup");

    char setup[256];
    GetClientCookie(client, g_hSavedSetupCookie, setup, sizeof(setup));

    char weapons[4][32] = { "None", "None", "None", "None" }; // Default to "None"
    
    if (strlen(setup) > 0) {
        ExplodeString(setup, ";", weapons, sizeof(weapons), sizeof(weapons[]));
    }

    char display[128];
    Format(display, sizeof(display), "Primary: %s", GetWeaponDisplayName(weapons[0]));
    menu.AddItem("primary", display, ITEMDRAW_DISABLED);
    Format(display, sizeof(display), "Secondary: %s", GetWeaponDisplayName(weapons[1]));
    menu.AddItem("secondary", display, ITEMDRAW_DISABLED);
    Format(display, sizeof(display), "Grenade: %s", GetWeaponDisplayName(weapons[2]));
    menu.AddItem("grenade", display, ITEMDRAW_DISABLED);
    Format(display, sizeof(display), "Knife: %s", GetWeaponDisplayName(weapons[3]));
    menu.AddItem("knife", display, ITEMDRAW_DISABLED);

    menu.AddItem("change", "Overwrite Setup");
    menu.AddItem("clear", "Clear Saved Setup");

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}


public int ViewSavedSetupMenuHandler(Menu menu, MenuAction action, int client, int param2) {
    if (action == MenuAction_Select) {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "change")) {
            SaveClientSetup(client);
            PrintToChat(client, "[\x04ZMarket\x01] Your setup has been updated.");
        } 
        else if (StrEqual(info, "clear")) {
            ClearClientSetup(client);
            PrintToChat(client, "[\x04ZMarket\x01] Your saved setup has been cleared.");
        }

        ShowViewSavedSetupMenu(client);
    } 
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
        ShowZMarketMenu(client);
    } 
    else if (action == MenuAction_End) {
        delete menu;
    }
    return 0;
}


void ShowBuyWeaponsMenu(int client) {
    Menu menu = new Menu(BuyWeaponsMenuHandler);
    menu.SetTitle("Buy Weapons");
    menu.AddItem("pistols", "Pistols");
    menu.AddItem("shotgun", "Shotguns");
    menu.AddItem("smg", "SMGs");
    menu.AddItem("rifle", "Rifles");
    menu.AddItem("sniper", "Snipers");
    menu.AddItem("machinegun", "Machine Guns");
    menu.Display(client, MENU_TIME_FOREVER);
}

public int BuyWeaponsMenuHandler(Menu menu, MenuAction action, int client, int param2) {
    if (action == MenuAction_Select) {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        WeaponCategory category;
        if (StrEqual(info, "pistols")) category = Category_Pistol;
        else if (StrEqual(info, "shotgun")) category = Category_Shotgun;
        else if (StrEqual(info, "smg")) category = Category_SMG;
        else if (StrEqual(info, "rifle")) category = Category_Rifle;
        else if (StrEqual(info, "sniper")) category = Category_Sniper;
        else if (StrEqual(info, "machinegun")) category = Category_MachineGun;
        ShowWeaponCategoryMenu(client, category);
    } else if (action == MenuAction_End) {
        delete menu;
    }
    return 0;
}

void BuySavedSetup(int client) {
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
        return;
    }
    if (ZRiot_IsClientZombie(client)) {
        PrintToChat(client, "[\x04ZMarket\x01] Zombies cannot use saved setups.");
        return;
    }

    char setup[256];
    GetClientSetupCookie(client, setup, sizeof(setup));

    if (strlen(setup) == 0) {
        PrintToChat(client, "[\x04ZMarket\x01] You have no saved setup.");
        return;
    }

    int totalCost = GetTotalSetupCost(setup);

    int playerMoney = GetClientMoney(client);

    if (playerMoney < totalCost) {
        PrintToChat(client, "[\x04ZMarket\x01] You don't have enough money to purchase your saved setup. You need %d more.", totalCost - playerMoney);
        return;
    }

    DeductPlayerMoney(client, totalCost);

    StripAllWeapons(client);

    char weapons[6][32];
    int count = ExplodeString(setup, ";", weapons, sizeof(weapons), sizeof(weapons[]));

    for (int i = 0; i < count; i++) {
        if (strlen(weapons[i]) > 0) {
            GivePlayerItem(client, weapons[i]);
        }
    }

    PrintToChat(client, "[\x04ZMarket\x01] Your saved setup has been restored. You spent %d.", totalCost);
}


void ToggleAutoRebuy(int client) {
    g_bAutoRebuy[client] = !g_bAutoRebuy[client];
    SetClientCookie(client, g_hAutoRebuyCookie, g_bAutoRebuy[client] ? "1" : "0");
    PrintToChat(client, "[\x04ZMarket\x01] Auto-Rebuy is now %s.", g_bAutoRebuy[client] ? "Yes" : "No");
}

void ShowWeaponCategoryMenu(int client, WeaponCategory category) {
    Menu menu = new Menu(WeaponCategoryMenuHandler);
    menu.SetTitle("Select a Weapon");

    bool found = false;
    for (int i = 0; i < g_WeaponData.Length; i++) {
        WeaponData weapon;
        g_WeaponData.GetArray(i, weapon, sizeof(WeaponData));

        if (weapon.Category == category) {
            char weaponDisplay[64];
            if (weapon.Restricted) {
                Format(weaponDisplay, sizeof(weaponDisplay), "%s (Restricted)", weapon.DisplayName);
                menu.AddItem(weapon.WeaponEntity, weaponDisplay, ITEMDRAW_DISABLED);
            } else {
                strcopy(weaponDisplay, sizeof(weaponDisplay), weapon.DisplayName);
                menu.AddItem(weapon.WeaponEntity, weaponDisplay);
            }
            found = true;
        }
    }

    if (!found) {
        PrintToChat(client, "[\x04ZMarket\x01] No weapons available in this category.");
        delete menu;
        return;
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}


public int WeaponCategoryMenuHandler(Menu menu, MenuAction action, int client, int param2) {
    if (action == MenuAction_Select) {
        char weaponEntity[32];
        menu.GetItem(param2, weaponEntity, sizeof(weaponEntity));

        for (int i = 0; i < g_WeaponData.Length; i++) {
            WeaponData weapon;
            g_WeaponData.GetArray(i, weapon, sizeof(WeaponData));

            if (StrEqual(weapon.WeaponEntity, weaponEntity)) {
                GivePlayerItem(client, weapon.WeaponEntity);
                PrintToChat(client, "[\x04ZMarket\x01] You have purchased %s.", weapon.DisplayName);
                return 0;
            }
        }
    } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
        ShowBuyWeaponsMenu(client);
    } else if (action == MenuAction_End) {
        delete menu;
    }
    return 0;
}

void StripAllWeapons(int client) {
    for (int i = 0; i < 5; i++) {
        int weapon = GetPlayerWeaponSlot(client, i);
        if (weapon != -1) {
            RemovePlayerItem(client, weapon);
        }
    }
}

int GetTotalSetupCost(const char[] setup) {
    char weapons[6][32];
    int count = ExplodeString(setup, ";", weapons, sizeof(weapons), sizeof(weapons[]));
    
    int totalCost = 0;

    for (int i = 0; i < count; i++) {
        if (strlen(weapons[i]) > 0) {
            WeaponData weapon;
            bool found = false;
            for (int j = 0; j < g_WeaponData.Length; j++) {
                g_WeaponData.GetArray(j, weapon, sizeof(WeaponData));
                if (StrEqual(weapon.WeaponEntity, weapons[i])) {
                    totalCost += weapon.Price;
                    found = true;
                }
            }

            if (!found) {
                LogToFile("Weapon %s not found in the weapon data.", weapons[i]);
            }
        }
    }

    return totalCost;
}


int GetClientMoney(int client) {
    return GetEntProp(client, Prop_Send, "m_iAccount");
}

void SetClientMoney(int client, int amount) {
    SetEntProp(client, Prop_Send, "m_iAccount", amount);
}

void DeductPlayerMoney(int client, int amount) {
    SetClientMoney(client, GetClientMoney(client) - amount);
}


char[] GetWeaponDisplayName(const char[] weaponEntity) {
    static char displayName[64];

    for (int i = 0; i < g_WeaponData.Length; i++) {
        WeaponData weapon;
        g_WeaponData.GetArray(i, weapon);

        if (StrEqual(weaponEntity, weapon.WeaponEntity)) {
            strcopy(displayName, sizeof(displayName), weapon.DisplayName);
            return displayName;
        }
    }

    strcopy(displayName, sizeof(displayName), weaponEntity);  
    return displayName;
}

void ZRiot_GivePlayerAmmo(int client, int ammoIndex, int amount) {
    if (ammoIndex != -1) {
        SetEntProp(client, Prop_Send, "m_iAmmo", amount, _, ammoIndex);
    }
}

bool IsPlayerInBuyZone(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return false;

    return GetEntProp(client, Prop_Send, "m_bInBuyZone") == 1;
}

bool IsValidClient(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}
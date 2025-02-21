enum WeaponCategory {
    Category_Invalid = -1, 
    Category_Pistol, 
    Category_Shotgun, 
    Category_SMG, 
    Category_Rifle, 
    Category_Sniper, 
    Category_MachineGun, 
    Category_Grenade, 
    Category_Knife 
};

enum struct WeaponData {
    char WeaponName[32];
    char DisplayName[64];
    char WeaponEntity[32];
    char AmmoEntity[64];
    char BuyCommands[32];
    WeaponCategory Category;
    int Price;
    int AmmoPrice;
    int Slot;
    bool Restricted;
    KeyValues kvData;
}

ArrayList g_WeaponData;

void LoadWeaponData() {
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/zmarket/weapons.txt");

    if (!FileExists(path)) {
        SetFailState("Could not find weapons.txt in configs folder.");
    }

    KeyValues kv = new KeyValues("weapons");
    if (!kv.ImportFromFile(path)) {
        SetFailState("Failed to import weapons.txt.");
    }

    if (!kv.GotoFirstSubKey()) {
        SetFailState("No weapon data found in weapons.txt.");
    }

    g_WeaponData = new ArrayList(sizeof(WeaponData));

    do {
        WeaponData weapon;
        
        kv.GetSectionName(weapon.WeaponName, sizeof(weapon.WeaponName));
        kv.GetString("weapon_name", weapon.DisplayName, sizeof(weapon.DisplayName));
        kv.GetString("weaponentity", weapon.WeaponEntity, sizeof(weapon.WeaponEntity));
        kv.GetString("buycommand", weapon.BuyCommands, sizeof(weapon.BuyCommands));

        char category[32];
        kv.GetString("weapontype", category, sizeof(category));
        weapon.Category = GetWeaponCategory(category);

        weapon.Price = kv.GetNum("zmarketprice", 0);
        weapon.AmmoPrice = kv.GetNum("ammoprice", 0);
        weapon.Slot = kv.GetNum("weaponslot", -1);

        char restrictValue[8];
        kv.GetString("restrictdefault", restrictValue, sizeof(restrictValue), "no");
        weapon.Restricted = StrEqual(restrictValue, "yes", false);

        weapon.kvData = new KeyValues(weapon.WeaponName);
        weapon.kvData.ImportFromFile(path);

        if (weapon.Category != Category_Invalid) {
            g_WeaponData.PushArray(weapon);

            char commands[32][32];
            int count = ExplodeString(weapon.BuyCommands, ",", commands, sizeof(commands), sizeof(commands[]));

            for (int i = 0; i < count; i++) {
                TrimString(commands[i]);
                if (commands[i][0] != '\0') {
                    RegConsoleCmd(commands[i], Command_BuyWeaponDirect, weapon.DisplayName);
                    
                    if (StrContains(commands[i], "sm_", false) != 0) {
                        char smCommand[40];
                        Format(smCommand, sizeof(smCommand), "sm_%s", commands[i]);
                        RegConsoleCmd(smCommand, Command_BuyWeaponDirect, weapon.DisplayName);
                    }
                    PrintToServer("[DEBUG] Registered Command: %s for Weapon: %s", commands[i], weapon.DisplayName);
                }
            }
        }
    } while (kv.GotoNextKey());

    delete kv;
}


WeaponCategory GetWeaponCategory(const char[] type) {
    char categories[2][32];
    int count = ExplodeString(type, ",", categories, sizeof(categories), sizeof(categories[]));

    for (int i = 0; i < count; i++) {
        TrimString(categories[i]);

        if (StrEqual(categories[i], "Pistol", false)) return Category_Pistol;
        if (StrEqual(categories[i], "Shotgun", false)) return Category_Shotgun;
        if (StrEqual(categories[i], "SMG", false)) return Category_SMG;
        if (StrEqual(categories[i], "Rifle", false)) return Category_Rifle;
        if (StrEqual(categories[i], "Sniper", false)) return Category_Sniper;
        if (StrEqual(categories[i], "Machine Gun", false)) return Category_MachineGun;
        if (StrEqual(categories[i], "Grenade", false)) return Category_Grenade;
        if (StrEqual(categories[i], "Knife", false)) return Category_Knife;
    }

    return Category_Invalid;
}


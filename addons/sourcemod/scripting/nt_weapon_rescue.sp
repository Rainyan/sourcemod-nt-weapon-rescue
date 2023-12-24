#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.1.0"


bool _late;
bool _is_dropping_wep;
int _weapon = INVALID_ENT_REFERENCE;

public Plugin myinfo = {
	name = "NT Weapon Rescue",
	description = "If a weapon falls under the level, bring it back.",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-nt-weapon-rescue"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	_late = late;
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	GameData gd = LoadGameConfigFile("neotokyo/weapon_rescue");
	if (!gd)
	{
		SetFailState("Failed to load GameData");
	}
	DynamicDetour dd = DynamicDetour.FromConf(gd, "Fun_CEngineTrace__GetPointContents");
	if (!dd)
	{
		SetFailState("Failed to create dynamic detour");
	}
	if (!dd.Enable(Hook_Post, GetPointContents))
	{
		SetFailState("Failed to detour");
	}
	delete dd;
	delete gd;

	if (_late)
	{
		int i = 1;
		for (; i <= MaxClients; ++i)
		{
			if (IsClientInGame(i))
			{
				HookWeaponDrop(i);
			}
		}
	}

	if (!HookEventEx("game_round_end", OnRoundEnd, EventHookMode_Pre))
	{
		SetFailState("Failed to hook event");
	}
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	_is_dropping_wep = false;
}

public void OnMapEnd()
{
	_is_dropping_wep = false;
}

public void OnClientPutInServer(int client)
{
	HookWeaponDrop(client);
}

public void OnWeaponDrop(int client, int weapon)
{
	_weapon = EntIndexToEntRef(weapon);
	_is_dropping_wep = true;
}

public MRESReturn GetPointContents(DHookReturn hReturn, DHookParam hParams)
{
	if (!_is_dropping_wep || !(hReturn.Value & CONTENTS_SOLID))
	{
		return MRES_Ignored;
	}

	_is_dropping_wep = false;

	if (!IsValidEdict(_weapon))
	{
		return MRES_Ignored;
	}

	float pos[3];
	hParams.GetVector(1, pos);

	int failsafe;
	while (TR_PointOutsideWorld(pos))
	{
		pos[2] += 100.0;
		if (failsafe++ > 2)
		{
			return MRES_Ignored;
		}
	}

	// This function will also write to origin, so gotta delay this.
	DeferTeleportEntity(_weapon, pos);

	return MRES_Ignored;
}

void DeferTeleportEntity(int weapon_ref, const float pos[3])
{
	DataPack data;
	CreateDataTimer(0.2, Timer_DeferTeleportEnt, data,
		TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(weapon_ref);
	data.WriteFloatArray(pos, 3);
}

public Action Timer_DeferTeleportEnt(Handle timer, DataPack data)
{
	data.Reset();
	int weapon = data.ReadCell();
	if (IsValidEdict(weapon))
	{
		float pos[3];
		data.ReadFloatArray(pos, sizeof(pos));
		float vel[3] = { 0.0, 0.0, 4.0 };
		TeleportEntity(weapon, pos, NULL_VECTOR, vel);
	}
	return Plugin_Stop;
}

void HookWeaponDrop(int client)
{
	if (!SDKHookEx(client, SDKHook_WeaponDrop, OnWeaponDrop))
	{
		SetFailState("Failed to SDKHook");
	}
}
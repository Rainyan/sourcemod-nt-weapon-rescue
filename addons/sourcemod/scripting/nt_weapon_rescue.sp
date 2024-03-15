#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.1.1"


bool _late, _is_dropping_wep;
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

	DynamicDetour dd = DynamicDetour.FromConf(gd,
		"Fun_CEngineTrace__GetPointContents");
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
		for (int i = 1; i <= MaxClients; ++i)
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

public Action OnWeaponDrop(int client, int weapon)
{
	_weapon = EntIndexToEntRef(weapon);
	_is_dropping_wep = true;
	return Plugin_Continue;
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

	RequestFrame(DeferredTeleport, _weapon);

	return MRES_Ignored;
}

void DeferredTeleport(int base_ent_ref)
{
	if (!IsValidEntity(base_ent_ref))
	{
		return;
	}

	float mins[3], maxs[3], pos[3];
	GetEntPropVector(base_ent_ref, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(base_ent_ref, Prop_Send, "m_vecMaxs", maxs);
	GetEntPropVector(base_ent_ref, Prop_Send, "m_vecOrigin", pos);

#define MAX_TRIES 66 // avoid infinite loop
	float tmp[3];
	for (int i = 0; i <= MAX_TRIES; ++i)
	{
		if (i == 1)
		{
			// Bump a lot initially, to avoid weird nooks and crannies
			// right below the floor.
			pos[2] += 3.0 * (maxs[2] - mins[2]) + 1.0;
		}
		// Don't bump on initial run, in case we actually do have a good pos
		else if (i != 0)
		{
			pos[2] += maxs[2] - mins[2] + 1.0;
		}

		// Origin out of bounds?
		if (TR_GetPointContents(pos) & CONTENTS_SOLID)
		{
			continue;
		}

		// Mins out of bounds?
		AddVectors(pos, mins, tmp);
		if (TR_GetPointContents(tmp) & CONTENTS_SOLID)
		{
			continue;
		}

		// Maxs out of bounds?
		AddVectors(pos, maxs, tmp);
		if (TR_GetPointContents(tmp) & CONTENTS_SOLID)
		{
			continue;
		}

		break; // found good position
	}

	float zeroed[3]; // kill any momentum for the rescue
	TeleportEntity(base_ent_ref, pos, NULL_VECTOR, zeroed);
}

void HookWeaponDrop(int client)
{
	if (!SDKHookEx(client, SDKHook_WeaponDrop, OnWeaponDrop))
	{
		SetFailState("Failed to SDKHook");
	}
}
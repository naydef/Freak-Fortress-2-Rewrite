/*
	void Gamemode_MapStart()
	void Gamemode_RoundSetup()
	void Gamemode_RoundStart()
	void Gamemode_RoundEnd()
*/

static bool Waiting;
static float HealingFor;
static int WinnerOverride;
static Handle HudTimer[TFTeam_MAX];
static Handle SyncHud[TFTeam_MAX];
static bool HasBoss[TFTeam_MAX];

static int TeamColors[][] =
{
	{255, 255, 100, 255},
	{100, 255, 100, 255},
	{255, 100, 100, 255},
	{100, 100, 255, 255}
};

void Gamemode_PluginStart()
{
	for(int i; i<TFTeam_MAX; i++)
	{
		SyncHud[i] = CreateHudSynchronizer();
	}
}

void Gamemode_MapStart()
{
	//TODO: If a round as been played before, Waiting for Players will never end - Late loading without players on breaks FF2 currently
	Waiting = true;
	for(int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			Waiting = false;
			break;
		}
	}
}

void Gamemode_RoundSetup()
{
	Debug("Gamemode_RoundSetup %d", Waiting ? 1 : 0);
	
	HealingFor = 0.0;
	RoundStatus = 0;
	WinnerOverride = -1;
	for(int client=1; client<=MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			Client(client).ResetByRound();
			Bosses_Remove(client);
		}
	}
	
	if(Enabled)
	{
		if(Waiting)
		{
			CvarTournament.BoolValue = true;
			CvarMovementFreeze.BoolValue = false;
			ServerCommand("mp_waitingforplayers_restart 1");
			Debug("mp_waitingforplayers_restart 1");
		}
		else if(!GameRules_GetProp("m_bInWaitingForPlayers", 1))
		{
			CreateTimer(CvarPreroundTime.FloatValue / 2.857143, Gamemode_IntroTimer, _, TIMER_FLAG_NO_MAPCHANGE);
			
			int bosses = CvarBossVsBoss.IntValue;
			if(bosses > 0)	// Boss vs Boss
			{
				int reds;
				int[] red = new int[MaxClients];
				for(int client=1; client<=MaxClients; client++)
				{
					if(IsClientInGame(client) && GetClientTeam(client) > TFTeam_Spectator)
						red[reds++] = client;
				}
					
				if(reds)
				{
					SortIntegers(red, reds, Sort_Random);
					
					int team = TFTeam_Red + (GetTime() % 2);
					for(int i; i<reds; i++)
					{
						ChangeClientTeam(red[i], team);
						team = team == TFTeam_Red ? TFTeam_Blue : TFTeam_Red;
					}
					
					reds = GetBossQueue(red, MaxClients, TFTeam_Red);
					
					int[] blu = new int[MaxClients];
					int blus = GetBossQueue(blu, MaxClients, TFTeam_Blue);
					
					for(int i; i<bosses && i<blus; i++)
					{
						if(!Client(blu[i]).IsBoss)
						{
							Bosses_Create(blu[i], Preference_PickBoss(blu[i], TFTeam_Blue), TFTeam_Blue);
							Client(blu[i]).Queue = 0;
						}
					}
					
					for(int i; i<bosses && i<reds; i++)
					{
						if(!Client(red[i]).IsBoss)
						{
							Bosses_Create(red[i], Preference_PickBoss(red[i], TFTeam_Red), TFTeam_Red);
							Client(red[i]).Queue = 0;
						}
					}
				}
			}
			else	// Standard FF2
			{
				int[] boss = new int[1];
				if(GetBossQueue(boss, 1))
				{
					int team;
					int special = Preference_PickBoss(boss[0]);
					ConfigMap cfg;
					if((cfg=Bosses_GetConfig(special)))
					{
						cfg.GetInt("bossteam", team);
						switch(team)
						{
							case TFTeam_Spectator:
							{
								team = TFTeam_Red + (GetTime() % 2);
							}
							case TFTeam_Red, TFTeam_Blue:
							{
								
							}
							default:
							{
								team = TFTeam_Blue;
							}
						}
						
						Bosses_Create(boss[0], special, team);
						Client(boss[0]).Queue = 0;
					}
					else
					{
						char buffer[64];
						Bosses_GetCharset(Charset, buffer, sizeof(buffer));
						LogError("[!!!] Failed to find a valid boss in %s (#%d)", buffer, Charset);
					}
					
					int count;
					int[] players = new int[MaxClients];
					for(int client=1; client<=MaxClients; client++)
					{
						if(!Client(client).IsBoss && IsClientInGame(client) && GetClientTeam(client) > TFTeam_Spectator)
							players[count++] = client;
					}
					
					team = team == TFTeam_Red ? TFTeam_Blue : TFTeam_Red;
					for(int i; i<count; i++)
					{
						ChangeClientTeam(players[i], team);
					}
				}
				else	// No boss, normal Arena time
				{
					int count;
					int[] players = new int[MaxClients];
					for(int client=1; client<=MaxClients; client++)
					{
						if(IsClientInGame(client) && GetClientTeam(client) > TFTeam_Spectator)
							players[count++] = client;
					}
					
					if(count)
					{
						SortIntegers(players, count, Sort_Random);
						
						int team = TFTeam_Red + (GetTime() % 2);
						for(int i; i<count; i++)
						{
							ChangeClientTeam(players[i], team);
							team = team == TFTeam_Red ? TFTeam_Blue : TFTeam_Red;
						}
					}
				}
			}
		}
	}
}

public void TF2_OnWaitingForPlayersStart()
{
	Debug("TF2_OnWaitingForPlayersStart");
	if(GameRules_GetProp("m_bInWaitingForPlayers", 1) && Enabled)
	{
		Waiting = false;
		CvarTournament.BoolValue = false;
		CreateTimer(4.0, Gamemode_TimerRespawn, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	}
}

public void TF2_OnWaitingForPlayersEnd()
{
	Debug("TF2_OnWaitingForPlayersEnd");
	if(Enabled)
		CvarMovementFreeze.BoolValue = true;
}

public Action Gamemode_TimerRespawn(Handle timer)
{
	if(!GameRules_GetProp("m_bInWaitingForPlayers", 1))
		return Plugin_Stop;

	GameRules_SetProp("m_bInWaitingForPlayers", false, 1);
	for(int client=1; client<=MaxClients; client++)
	{
		if(IsClientInGame(client) && !IsPlayerAlive(client) && GetClientTeam(client) > 1 && GetEntProp(client, Prop_Send, "m_iDesiredPlayerClass"))
			TF2_RespawnPlayer(client);
	}
	GameRules_SetProp("m_bInWaitingForPlayers", true, 1);
	return Plugin_Continue;
}

public Action Gamemode_IntroTimer(Handle timer)
{
	for(int client=1; client<=MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			if(!Client(client).IsBoss || !ForwardOld_OnMusicPerBoss(client) || !Bosses_PlaySoundToClient(client, client, "sound_begin"))
			{
				int team = GetClientTeam(client);
				for(int i; i<MaxClients; i++)
				{
					int boss = FindClientOfBossIndex(i);
					if(boss != -1 && GetClientTeam(boss) != team && Bosses_PlaySoundToClient(boss, client, "sound_begin"))
						break;
				}
			}
		}
	}
	return Plugin_Continue;
}

void Gamemode_RoundStart()
{
	RoundStatus = 1;
	
	if(Enabled && !GameRules_GetProp("m_bInWaitingForPlayers", 1))
	{
		Events_CheckAlivePlayers();
		
		int[] merc = new int[MaxClients];
		int[] boss = new int[MaxClients];
		int mercs, bosses;
		
		for(int client=1; client<=MaxClients; client++)
		{
			if(IsClientInGame(client))
			{
				if(Client(client).IsBoss)
				{
					boss[bosses++] = client;
				}
				else
				{
					merc[mercs++] = client;
					
					if(IsPlayerAlive(client))
					{
						TF2_RegeneratePlayer(client);
						
						int entity = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
						if(IsValidEntity(entity) && HasEntProp(entity, Prop_Send, "m_flChargeLevel"))
							SetEntPropFloat(entity, Prop_Send, "m_flChargeLevel", 0.0);
					}
				}
			}
		}
		
		char buffer[64];
		bool specTeam = CvarSpecTeam.BoolValue;
		for(int i; i<bosses; i++)
		{
			int team = GetClientTeam(boss[i]);
			int amount = 0;
			for(int a = specTeam ? TFTeam_Unassigned : TFTeam_Spectator; a<TFTeam_MAX; a++)
			{
				if(team != a)
					amount += PlayersAlive[a];
			}
			
			int maxhealth = Bosses_SetHealth(boss[i], amount);
			int maxlives = Client(boss[i]).MaxLives;
			
			for(int a; a<mercs; a++)
			{
				Bosses_GetBossNameCfg(Client(boss[i]).Cfg, buffer, sizeof(buffer), GetClientLanguage(merc[a]));
				if(maxlives > 1)
				{
					FPrintToChatEx(merc[a], boss[i], "%t", "Boss Spawned As Lives", boss[i], buffer, maxhealth, maxlives);
					if(bosses == 1)
						ShowGameText(merc[a], _, 0, "%t", "Boss Spawned As Lives", boss[i], buffer, maxhealth, maxlives);
				}
				else
				{
					FPrintToChatEx(merc[a], boss[i], "%t", "Boss Spawned As", boss[i], buffer, maxhealth);
					if(bosses == 1)
						ShowGameText(merc[a], _, 0, "%t", "Boss Spawned As", boss[i], buffer, maxhealth);
				}
			}
		}
		
		Music_RoundStart();
	}
}

void Gamemode_OverrideWinner(int team=-1)
{
	WinnerOverride = team;
}

void Gamemode_RoundEnd(int winteam)
{
	RoundStatus = 2;
	
	// If we overrided the winner, such as spec teams
	int winner = WinnerOverride == -1 ? winteam : WinnerOverride;
	
	int[] clients = new int[MaxClients];
	int[] teams = new int[MaxClients];
	int total;
	
	for(int client=1; client<=MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			teams[total] = GetClientTeam(client);
			clients[total++] = client;
		}
	}
	
	Music_RoundEnd(clients, total, winner);
	
	/*
		Welcome to overly complicated land:
		
		Center Huds:
			Checks for "group" to find team name for that team lowest boss index takes prio
			Gathers health and max health of that team
			Saves lastBoss[] in case of solo boss
		
		Sounds:
			Gets the lowest boss index of each team that have sound_win (if they won) or sound_fail (if they lost and alive)
			Other bosses play sound_win on themself if they also won
			Other bosses play sound_fail on themself if the global sound wasn't a sound_win, they lost, and alive or if no there was no global sound
		
			I hear my win sound			- My team won, I have a sound_win, Lowest boss index of my team
			I hear my lose sound		- My team lost, I have a sound_fail, Winners don't have a sound_win, I'm alive or there wasn't a global lose sound
			I hear other's win sound	- My team lost or my team won but I don't have sound_win
			I hear other's lose sound	- Winners don't have a sound_win, My team won or don't have a sound_fail or I'm dead and there was a global lose sound
			I hear nothing				- No winners have sound_win and no losers have sound_fail
	*/
	
	char buffer[64];
	int bosses[TFTeam_MAX], totalHealth[TFTeam_MAX], totalMax[TFTeam_MAX], lastBoss[TFTeam_MAX], lowestBoss[TFTeam_MAX], lowestIndex[TFTeam_MAX], teamName[TFTeam_MAX], teamIndex[TFTeam_MAX];
	for(int i; i<total; i++)
	{
		if(Client(clients[i]).IsBoss)
		{
			bosses[teams[i]]++;					// If it's a team or a single boss
			lastBoss[teams[i]] = clients[i];	// For single boss health left HUD
			
			bool alive = IsPlayerAlive(clients[i]);
			int index = Client(clients[i]).Index;
			
			// Find the best boss to play their sound
			if(!lowestBoss[teams[i]] || index < lowestIndex[teams[i]])
			{
				bool found = (alive || winner == teams[i]);
				if(found)
					found = Client(clients[i]).Cfg.GetSection(winner == teams[i] ? "sound_win" : "sound_fail") != null;
				
				if(found)
				{
					lowestBoss[teams[i]] = clients[i];
					lowestIndex[teams[i]] = index;
				}
			}
			
			int maxhealth = Client(clients[i]).MaxHealth * Client(clients[i]).MaxLives;
			totalMax[teams[i]] += maxhealth;
			
			// Show chat message version
			if(alive)
			{
				int health = Client(clients[i]).Health;
				if(health > 0)
				{
					totalHealth[teams[i]] += health;
					
					for(int a; a<total; a++)
					{
						Bosses_GetBossNameCfg(Client(clients[i]).Cfg, buffer, sizeof(buffer), GetClientLanguage(clients[a]));
						FPrintToChatEx(clients[a], clients[i], "%t", "Boss Had Health Left", buffer, clients[i], health, maxhealth);
					}
				}
			}
			
			// Use a team name if a boss has one
			if(!teamName[teams[i]] || index < teamIndex[teams[i]])
			{
				if(Client(clients[i]).Cfg.GetSize("group"))
				{
					teamName[teams[i]] = clients[i];
					teamIndex[teams[i]] = index;
				}
			}
			
			// Move em back from spec team
			if(teams[i] <= TFTeam_Spectator)
				SDKCall_ChangeClientTeam(clients[i], teams[i] + 2);
		}
	}
	
	float time = CvarBonusRoundTime.FloatValue - 1.0;
	for(int i; i<TFTeam_MAX; i++)
	{
		if(HasBoss[i])
		{
			HasBoss[i] = false;
			
			if(bosses[i])
			{
				SetHudTextParamsEx(-1.0, 0.4 - (i * 0.05), time, TeamColors[i], TeamColors[winner], 2, 2.0, 0.5, 1.0);
				for(int a; a<total; a++)
				{
					SetGlobalTransTarget(clients[a]);
					
					if(teamName[i])	// Team with a Name
					{
						Bosses_GetBossNameCfg(Client(teamName[i]).Cfg, buffer, sizeof(buffer), GetClientLanguage(clients[a]), "group");
						ShowSyncHudText(clients[a], SyncHud[i], "%t", "Team Had Health Left", "_s", buffer, totalHealth[i], totalMax[i]);
					}
					else if(bosses[i] == 1)	// Solo Boss
					{
						Bosses_GetBossNameCfg(Client(lastBoss[i]).Cfg, buffer, sizeof(buffer), GetClientLanguage(clients[a]));
						ShowSyncHudText(clients[a], SyncHud[i], "%t", "Boss Had Health Left Hud", buffer, lastBoss[i], totalHealth[i], totalMax[i]);
					}
					else	// Team without a Name
					{
						FormatEx(buffer, sizeof(buffer), "Team %d", i);
						ShowSyncHudText(clients[a], SyncHud[i], "%t", "Team Had Health Left Hud", buffer, totalHealth[i], totalMax[i]);
					}
				}
			}
			else
			{
				for(int a; a<total; a++)
				{
					ClearSyncHud(clients[a], SyncHud[i]);
				}
			}
		}
		
		if(HudTimer[i])
		{
			KillTimer(HudTimer[i]);
			HudTimer[i] = null;
		}
	}
	
	// Figure out which boss we should play
	int globalBoss, globalTeam;
	if(lowestBoss[winner])
	{
		globalBoss = lowestBoss[winner];
		globalTeam = winner;
	}
	else
	{
		int index = 99;
		for(int i; i<TFTeam_MAX; i++)
		{
			if(lowestIndex[i] < index)
			{
				globalBoss = lowestBoss[i];
				globalTeam = i;
			}
		}
	}
	
	// Gather who hears global and play locals
	int globalCount;
	int[] globalSound = new int[total];
	for(int i; i<total; i++)
	{
		if(clients[i] != globalBoss && Client(clients[i]).IsBoss)
		{
			if(winner == teams[i])
			{
				// Play sound_win for themself if they are on the winning team
				if(Bosses_PlaySoundToClient(clients[i], clients[i], "sound_win"))
					continue;
			}
			else if(globalTeam != winner)
			{
				// Play sound_fail for themself if: Global sound wasn't a sound_win, Global sound didn't exist or they're alive
				if(!globalBoss || IsPlayerAlive(clients[i]))
				{
					if(Bosses_PlaySoundToClient(clients[i], clients[i], "sound_fail"))
						continue;
				}
			}
		}
		
		globalSound[globalCount++] = clients[i];
	}
	
	// Play global sound
	if(globalBoss)
		Bosses_PlaySound(globalBoss, globalSound, globalCount, globalTeam == winner ? "sound_win" : "sound_fail");
	
	// Give Queue Points
	if(Enabled && total)
	{
		int[] points = new int[MaxClients+1];
		for(int i; i<total; i++)
		{
			points[clients[i]] = Client(clients[i]).IsBoss ? 0 : 10;
		}
		
		if(ForwardOld_OnAddQueuePoints(points, MaxClients+1))
		{
			for(int i; i<total; i++)
			{
				Client(clients[i]).Queue += points[clients[i]];
			}
		}
	}
}

void Gamemode_UpdateHUD(int team, bool healing=false, bool nobar=false)
{
	if(!Enabled || RoundStatus == 1)
	{
		int setting = CvarHealthBar.IntValue;
		if(setting)
		{
			int lastCount, count;
			if(HasBoss[team])
			{
				for(int i; i<TFTeam_MAX; i++)
				{
					if(HasBoss[i])
						count++;
				}
				
				lastCount = count;
			}
			else
			{
				count++;
				HasBoss[team] = true;
				for(int i; i<TFTeam_MAX; i++)
				{
					if(i != team && HasBoss[i])
					{
						count++;
						lastCount++;
						Gamemode_UpdateHUD(i, healing, true);
					}
				}
			}
			
			int[] clients = new int[MaxClients];
			int total;
			
			for(int client=1; client<=MaxClients; client++)
			{
				if(IsClientInGame(client))
					clients[total++] = client;
			}
			
			int health, lives, maxhealth, maxcombined, combined, bosses;
			for(int i; i<total; i++)
			{
				if(Client(clients[i]).IsBoss && GetClientTeam(clients[i]) == team)
				{
					if(IsPlayerAlive(clients[i]))
					{
						bosses++;
						int hp = GetClientHealth(clients[i]);
						if(hp > 0)
						{
							health += hp;
							lives += Client(clients[i]).Lives;
							combined += Client(clients[i]).Health;
						}
					}
					
					int maxhp = SDKCall_GetMaxHealth(clients[i]);
					maxhealth += maxhp;
					maxcombined += maxhp + (Client(clients[i]).MaxHealth * (Client(clients[i]).MaxLives - 1));
				}
			}
			
			if(setting > 1)
			{
				if(count > 1)
				{
					float x = (team == TFTeam_Red || team == TFTeam_Spectator) ? 0.53 : 0.43;
					float y = team <= TFTeam_Spectator ? 0.18 : 0.12;
					for(int i; i<total; i++)
					{
						if(GetClientButtons(clients[i]) & IN_SCORE)
							continue;
						
						if(IsClientObserver(clients[i]))
						{
							SetHudTextParamsEx(x, y+0.1, 3.0, TeamColors[team], TeamColors[team], 0, 0.35, 0.0, 0.1);
						}
						else
						{
							SetHudTextParamsEx(x, y, 3.0, TeamColors[team], TeamColors[team], 0, 0.35, 0.0, 0.1);
						}
						
						if(bosses > 1)
						{
							ShowSyncHudText(clients[i], SyncHud[team], "%d", combined);
						}
						else if(lives > 1)
						{
							ShowSyncHudText(clients[i], SyncHud[team], "%d (x%d)", health, lives);
						}
						else
						{
							ShowSyncHudText(clients[i], SyncHud[team], "%d", health);
						}
					}
				}
				else
				{
					for(int i; i<total; i++)
					{
						if(GetClientButtons(clients[i]) & IN_SCORE)
							continue;
						
						if(IsClientObserver(clients[i]))
						{
							SetHudTextParams(-1.0, 0.22, 3.0, 200, 255, 200, 255, 0, 0.35, 0.0, 0.1);
						}
						else
						{
							SetHudTextParams(-1.0, 0.12, 3.0, 200, 255, 200, 255, 0, 0.35, 0.0, 0.1);
						}
						
						if(bosses > 1)
						{
							ShowSyncHudText(clients[i], SyncHud[team], "%d / %d", combined, maxcombined);
						}
						else if(lives > 1)
						{
							ShowSyncHudText(clients[i], SyncHud[team], "%d / %d (x%d)", health, maxhealth, lives);
						}
						else
						{
							ShowSyncHudText(clients[i], SyncHud[team], "%d / %d", health, maxhealth);
						}
					}
				}
			}
			
			float refresh = 2.8;
			if(setting == 1 || nobar)
			{
			}
			else if(count < 3)
			{
				int entity = MaxClients + 1;
				while((entity=FindEntityByClassname(entity, "eyeball_boss")) != -1)
				{
					if(GetEntProp(entity, Prop_Send, "m_iTeamNum") > TFTeam_Blue)
						break;
				}
				
				if(entity == -1)
				{
					entity = FindEntityByClassname(MaxClients+1, "monster_resource");
					if(entity == -1)
					{
						entity = CreateEntityByName("monster_resource");
						DispatchSpawn(entity);
					}
					
					float gameTime = GetGameTime();
					if(healing)
						HealingFor = gameTime + 1.0;
					
					if(HealingFor > gameTime)
					{
						SetEntProp(entity, Prop_Send, "m_iBossState", true);
						refresh = HealingFor - gameTime;
					}
					else
					{
						SetEntProp(entity, Prop_Send, "m_iBossState", false);
					}
					
					int amount;
					if(count == 2)
					{
						amount = SetTeamBasedHealthBar(combined, team);
					}
					else if(combined)
					{
						amount = combined * 255 / maxcombined;
						if(!amount)
							amount = 1;
					}
					
					SetEntProp(entity, Prop_Send, "m_iBossHealthPercentageByte", amount, 2);
				}
			}
			else if(lastCount < 3)
			{
				int entity = FindEntityByClassname(MaxClients+1, "monster_resource");
				if(entity != -1)
					RemoveEntity(entity);
			}
			
			if(HudTimer[team])
			{
				KillTimer(HudTimer[team]);
				HudTimer[team] = null;
			}
			
			if(health > 0 && RoundStatus != 2)
				HudTimer[team] = CreateTimer(refresh, Gamemode_UpdateHudTimer, team);
		}
	}
}

static int SetTeamBasedHealthBar(int health1, int team1)
{
	int team2;
	for(int i; i<TFTeam_MAX; i++)
	{
		if(i != team1 && HasBoss[i])
		{
			team2 = i;
			break;
		}
	}
	
	int health2 = 1;
	for(int client=1; client<=MaxClients; client++)
	{
		if(Client(client).IsBoss && GetClientTeam(client) == team2 && IsPlayerAlive(client))
		{
			int health = Client(client).Health;
			if(health > 0)
				health2 += health;
		}
	}
	
	if(team1 > team2)
	{
		if(health1 > health2)
		{
			health2 = RoundToCeil((1.0 - (float(health2) / float(health1) / 2.0)) * 255.0);
		}
		else if(health2)
		{
			health2 = health1 * 255 / health2 / 2;
			if(!health2)
				health2 = 1;
		}
	}
	else if(!health1)
	{
		health2 = 0;
	}
	else if(health2 > health1)
	{
		health2 = RoundToCeil((1.0 - (float(health1) / float(health2) / 2.0)) * 255.0);
	}
	else
	{
		health2 = health2 * 255 / health1 / 2;
		if(!health2)
			health2 = 1;
	}
	
	return health2;
}

public Action Gamemode_UpdateHudTimer(Handle timer, int team)
{
	HudTimer[team] = null;
	Gamemode_UpdateHUD(team);
	return Plugin_Continue;
}
/*
	void Music_PluginStart()
	void Music_ClientDisconnect()
	void Music_RoundStart()
	void Music_PlayerRunCmd(int client)
	void Music_PlayNextSong(int client=0)
	void Music_PlaySong(int[] clients, int numClients, const char[] sample="", int boss=0, const char[] name="", const char[] artist="", float duration=0.0, float volume=1.0, int pitch=SNDPITCH_NORMAL)
	void Music_PlaySongToClient(int client, const char[] sample="", int boss=0, const char[] name="", const char[] artist="", float duration=0.0, float volume=1.0, int pitch=SNDPITCH_NORMAL)
	void Music_PlaySongToAll(const char[] sample="", int boss=0, const char[] name="", const char[] artist="", float duration=0.0, float volume=1.0, int pitch=SNDPITCH_NORMAL)
	void Music_MainMenu(int client)
*/

static char CurrentTheme[MAXTF2PLAYERS][PLATFORM_MAX_PATH];
static int CurrentVolume[MAXTF2PLAYERS];
static int CurrentSource[MAXTF2PLAYERS];
static bool CurrentSourceType[MAXTF2PLAYERS];
static float NextThemeAt[MAXTF2PLAYERS];

void Music_PluginStart()
{
	RegFreakCmd("music", Music_Command, "Freak Fortress 2 Music Menu");
}

void Music_ClientDisconnect(int client)
{
	CurrentSourceType[client] = false;
}

void Music_RoundStart()
{
	for(int i=1; i<=MaxClients; i++)
	{
		if(NextThemeAt[i] == FAR_FUTURE)
			NextThemeAt[i] = 0.0;
	}
}

void Music_RoundEnd(int[] clients, int amount, int winner)
{
	for(int i; i<amount; i++)
	{
		if(CurrentTheme[clients[i]][0])
		{
			Music_PlaySongToClient(clients[i]);
			
			int boss;
			SoundEnum sound;
			if(CurrentSourceType[clients[i]])
			{
				ConfigMap cfg = Bosses_GetConfig(CurrentSource[clients[i]]);
				if(cfg)
				{
					if(GetClientTeam(clients[i]) == winner)
					{
						Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic_win", sound);
					}
					else if(winner || !Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic_stalemate", sound))
					{
						Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic_lose", sound);
					}
					
					if(!sound.Sound[0])
						Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic", sound);
				}
			}
			else
			{
				boss = GetClientUserId(CurrentSource[clients[i]]);
				if(boss)
				{
					if(GetClientTeam(boss) == winner)
					{
						Bosses_GetRandomSound(boss, "sound_outtromusic_win", sound);
					}
					else if(winner || !Bosses_GetRandomSound(boss, "sound_outtromusic_stalemate", sound))
					{
						Bosses_GetRandomSound(boss, "sound_outtromusic_lose", sound);
					}
					
					if(!sound.Sound[0])
						Bosses_GetRandomSound(boss, "sound_outtromusic", sound);
				}
			}
			
			if(sound.Sound[0])
				Music_PlaySongToClient(clients[i], sound.Sound, boss, sound.Name, sound.Artist, sound.Time, sound.Volume, sound.Pitch);
		}
	}
}

void Music_PlayerRunCmd(int client)
{
	if(RoundStatus != 2 && NextThemeAt[client] < GetEngineTime())
		Music_PlayNextSong(client);
}

void Music_PlayNextSong(int client=0)
{
	if(client)
	{
		NextThemeAt[client] = FAR_FUTURE;
		
		if(!Client(client).IsBoss || !ForwardOld_OnMusicPerBoss(client) || !Bosses_PlaySoundToClient(client, client, "sound_bgm"))
		{
			for(int i; i<MaxClients; i++)
			{
				int boss = FindClientOfBossIndex(i);
				if(boss != -1 && Bosses_PlaySoundToClient(boss, client, "sound_bgm"))
					return;
			}
		}
		
		Music_PlaySongToClient(client);
	}
	else
	{
		for(int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i))
				Music_PlayNextSong(i);
		}
	}
}

void Music_PlaySong(const int[] clients, int numClients, const char[] sample="", int boss=0, const char[] name="", const char[] artist="", float duration=0.0, float volume=1.0, int pitch=SNDPITCH_NORMAL)
{
	for(int i; i<numClients; i++)
	{
		if(CurrentTheme[clients[i]][0])
		{
			for(int a; a<CurrentVolume[clients[i]]; a++)
			{
				StopSound(clients[i], SNDCHAN_STATIC, CurrentTheme[clients[i]]);
			}
		}
	}
	
	if(sample[0])
	{
		char songName[64];
		if(name[0])
			strcopy(songName, sizeof(songName), name);
		
		char songArtist[64];
		if(artist[0])
			strcopy(songArtist, sizeof(songArtist), artist);
		
		float time = duration;
		char sample2[PLATFORM_MAX_PATH];
		strcopy(sample2, sizeof(sample2), sample);
		ForwardOld_OnMusic(sample2, time, songName, songArtist);
		
		if(time)
		{
			time += GetEngineTime();
		}
		else
		{
			time = FAR_FUTURE;
		}
		
		int count = RoundToCeil(volume);
		float vol = volume / float(count);
		
		int[] clients2 = new int[numClients];
		int amount;
		
		int userid = GetClientUserId(boss); // CHANGE
		for(int i; i<numClients; i++)
		{
			if(!Enabled || RoundStatus == 1)
			{
				if(!name[0])
					FormatEx(songName, sizeof(songName), "{default}%T", "Unknown Song", clients[i]);
				
				if(!artist[0])
					FormatEx(songArtist, sizeof(songArtist), "{default}%T", "Unknown Artist", clients[i]);
				
				FPrintToChat(clients[i], "%t", "Now Playing", songArtist, songName);
			}
			
			if(!Client(clients[i]).NoMusic)
			{
				clients2[amount++] = clients[i];
				strcopy(CurrentTheme[clients[i]], sizeof(CurrentTheme[]), sample2);
				NextThemeAt[clients[i]] = time;
				CurrentVolume[clients[i]] = count;
				CurrentSource[clients[i]] = userid;
			}
		}
		
		for(int i; i<count; i++)
		{
			EmitSound(clients2, amount, sample2, _, SNDCHAN_STATIC, SNDLEVEL_NONE, _, vol, pitch);
		}
	}
	else
	{
		for(int i; i<numClients; i++)
		{
			CurrentTheme[clients[i]][0] = 0;
			NextThemeAt[clients[i]] = FAR_FUTURE;
		}
	}
}

void Music_PlaySongToClient(int client, const char[] sample="", int boss=0, const char[] name="", const char[] artist="", float duration=0.0, float volume=1.0, int pitch=SNDPITCH_NORMAL)
{
	int clients[1];
	clients[0] = client;
	Music_PlaySong(clients, 1, sample, boss, name, artist, duration, volume, pitch);
}

void Music_PlaySongToAll(const char[] sample="", int boss=0, const char[] name="", const char[] artist="", float duration=0.0, float volume=1.0, int pitch=SNDPITCH_NORMAL)
{
	int[] clients = new int[MaxClients];
	int total;
	
	for(int client=1; client<=MaxClients; client++)
	{
		if(IsClientInGame(client))
			clients[total++] = client;
	}
	
	Music_PlaySong(clients, total, sample, boss, name, artist, duration, volume, pitch);
}

public Action Music_Command(int client, int args)
{
	if(client)
	{
		if(args > 0)
		{
			char buffer[16];
			GetCmdArg(1, buffer, sizeof(buffer));
			
			if(StrContains(buffer, "on", false) != -1 || StrEqual(buffer, "1") || StrContains(buffer, "enable", false) != -1)
			{
				Client(client).NoMusic = false;
				Music_PlayNextSong(client);
			}
			else if(StrContains(buffer, "off", false) != -1 || StrEqual(buffer, "0") || StrContains(buffer, "disable", false) != -1)
			{
				Client(client).NoMusic = true;
				Music_PlaySongToClient(client);
				FReplyToCommand(client, "%t", "Music Disabled");
			}
			else if(StrContains(buffer, "skip", false) != -1 || StrContains(buffer, "next", false) != -1)
			{
				CurrentSourceType[client] = false;
				Music_PlayNextSong(client);
			}
			else if(StrContains(buffer, "shuffle", false) != -1 || StrContains(buffer, "rand", false) != -1)
			{
				CurrentSourceType[client] = true;
				Music_PlayNextSong(client);
			}
			else if(StrContains(buffer, "track", false) != -1 || StrContains(buffer, "list", false) != -1)
			{
			}
			else
			{
				FReplyToCommand(client, "%t", "Music Unknown Arg", buffer);
			}
		}
		else
		{
			Music_MainMenu(client);
		}
	}
	else
	{
		ReplyToCommand(client, "[SM] %t", "Command is in-game only");
	}
	
	return Plugin_Handled;
}

void Music_MainMenu(int client)
{
	Menu menu = new Menu(Music_MainMenuH);
	
	SetGlobalTransTarget(buffer);
	menu.SetTitle("%t", "Music Menu");
	
			char buffer[128];
			if(ToggleMusic[client])
			{
				FormatEx(buffer, sizeof(buffer), "%t", "themes_disable");
				menu.AddItem(buffer, buffer);
				FormatEx(buffer, sizeof(buffer), "%t", "theme_skip");
				menu.AddItem(buffer, buffer);
				FormatEx(buffer, sizeof(buffer), "%t", "theme_shuffle");
				menu.AddItem(buffer, buffer);
				if(cvarSongInfo.IntValue >= 0)
				{
					FormatEx(buffer, sizeof(buffer), "%t", "theme_select");
					menu.AddItem(buffer, buffer);
				}
			}
			else
			{
				FormatEx(buffer, sizeof(buffer), "%t", "themes_enable");
				menu.AddItem(buffer, buffer);
			}
			menu.ExitButton = true;
			menu.Display(client, MENU_TIME_FOREVER);*/
}
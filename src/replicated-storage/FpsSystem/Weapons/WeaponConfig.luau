--!strict
-- ReplicatedStorage.FpsSystem.Weapons.WeaponConfig
local WeaponConfig = {}

export type SoundConfig = {
	Gunshot: string,
	Reload: string,
}

export type WeaponData = {
	Name: string,
	WeaponType: string?,         -- "Gun", "Throwable", etc.
	CasingType: string?,         -- Target model name in ReplicatedStorage.FpsSystem["Shell Casing"]
	FireRate: number,
	Damage: number,
	BulletsPerShot: number?,     -- Pellets per trigger pull (Shotguns)
	MagazineSize: number,
	MaxReserveAmmo: number,
	ReloadTime: number,
	Range: number,
	IsAutomatic: boolean,
	Sounds: SoundConfig,

	-- [[ SPREAD & ACCURACY PROPERTIES ]]
	BaseSpread: number,          -- Base hipfire spread angle (radians)
	AdsSpread: number,            -- Precision spread angle when ADS
	BloomPerShot: number,        -- Spread added per consecutive shot
	MaxBloom: number,            -- Maximum possible bloom radius
	BloomRecoveryRate: number,   -- Bloom decrease per second (when idle)
	MovementSpreadMult: number,  -- Penalty multiplier when moving/jumping

	-- [[ CAMERA RECOIL & KICK PROPERTIES ]]
	RecoilUp: number?,           -- Vertical pitch impulse
	RecoilSide: number?,         -- Horizontal yaw variance
	KickBack: number?,           -- Positional z-axis backward shove
}

local WeaponsManifest: { [string]: WeaponData } = {
	-- [[ FIREARMS ]]
	["AR"] = {
		Name = "Assault Rifle",
		WeaponType = "Gun",
		CasingType = "AR",
		FireRate = 0.12,
		Damage = 18,
		BulletsPerShot = 1,
		MagazineSize = 30,
		MaxReserveAmmo = 120,
		ReloadTime = 2.5,
		Range = 400,
		IsAutomatic = true,
		Sounds = {
			Gunshot = "rbxassetid://18458898055",
			Reload = "rbxassetid://140069224599018",
		},
		BaseSpread = 0.018, AdsSpread = 0.004, BloomPerShot = 0.008, MaxBloom = 0.065, BloomRecoveryRate = 0.15, MovementSpreadMult = 1.5,
		RecoilUp = 2.5, RecoilSide = 0.8, KickBack = 0.2,
	},
	["Handgun"] = {
		Name = "Tactical Handgun",
		WeaponType = "Gun",
		CasingType = "Handgun",
		FireRate = 0.22,
		Damage = 24,
		BulletsPerShot = 1,
		MagazineSize = 12,
		MaxReserveAmmo = 48,
		ReloadTime = 1.8,
		Range = 250,
		IsAutomatic = false,
		Sounds = {
			Gunshot = "rbxassetid://93683216880246",
			Reload = "rbxassetid://138248399002834",
		},
		BaseSpread = 0.015, AdsSpread = 0.002, BloomPerShot = 0.01, MaxBloom = 0.045, BloomRecoveryRate = 0.25, MovementSpreadMult = 1.2,
		RecoilUp = 3.5, RecoilSide = 0.5, KickBack = 0.3,
	},
	["SMG"] = {
		Name = "Submachine Gun",
		WeaponType = "Gun",
		CasingType = "SMG",
		FireRate = 0.08,
		Damage = 12,
		BulletsPerShot = 1,
		MagazineSize = 35,
		MaxReserveAmmo = 140,
		ReloadTime = 2.0,
		Range = 280,
		IsAutomatic = true,
		Sounds = {
			Gunshot = "rbxassetid://79206557251341",
			Reload = "rbxassetid://107027907490465",
		},
		BaseSpread = 0.03, AdsSpread = 0.008, BloomPerShot = 0.006, MaxBloom = 0.095, BloomRecoveryRate = 0.18, MovementSpreadMult = 1.6,
		RecoilUp = 1.8, RecoilSide = 1.2, KickBack = 0.15,
	},
	["Shotgun"] = {
		Name = "Pump Shotgun",
		WeaponType = "Gun",
		CasingType = "Shotgun",
		FireRate = 0.85,
		Damage = 12,             -- 12 damage per pellet x 8 pellets = 96 potential damage
		BulletsPerShot = 8,       -- Multi-pellet trigger discharge
		MagazineSize = 8,
		MaxReserveAmmo = 32,
		ReloadTime = 3.2,
		Range = 120,
		IsAutomatic = false,
		Sounds = {
			Gunshot = "rbxassetid://132711300701696",
			Reload = "rbxassetid://139827026287805",
		},
		BaseSpread = 0.07, AdsSpread = 0.04, BloomPerShot = 0.02, MaxBloom = 0.1, BloomRecoveryRate = 0.4, MovementSpreadMult = 1.5,
		RecoilUp = 8.0, RecoilSide = 1.5, KickBack = 0.6,
	},
	["Sniper Rifle"] = {
		Name = "Sniper Rifle",
		WeaponType = "Gun",
		CasingType = "Sniper",
		FireRate = 1.25,
		Damage = 100,
		BulletsPerShot = 1,
		MagazineSize = 5,
		MaxReserveAmmo = 20,
		ReloadTime = 3.5,
		Range = 1000,
		IsAutomatic = false,
		Sounds = {
			Gunshot = "rbxassetid://135333708100426",
			Reload = "rbxassetid://138635543016523",
		},
		BaseSpread = 0.06, AdsSpread = 0.0, BloomPerShot = 0.03, MaxBloom = 0.08, BloomRecoveryRate = 0.35, MovementSpreadMult = 3.5,
		RecoilUp = 10.0, RecoilSide = 0.5, KickBack = 0.8,
	},
}

function WeaponConfig.GetWeaponData(weaponIdentifier: string): WeaponData?
	-- 1. Direct dictionary key match (e.g. "AR", "Shotgun")
	local directMatch = WeaponsManifest[weaponIdentifier]
	if directMatch then 
		return directMatch 
	end

	-- 2. Fallback search by Name property (e.g. "Assault Rifle", "Pump Shotgun")
	for _, config in pairs(WeaponsManifest) do
		if config.Name == weaponIdentifier then
			return config
		end
	end

	warn(string.format("⚠️ [WeaponConfig] Weapon identifier '%s' not found!", weaponIdentifier))
	return nil
end

return WeaponConfig
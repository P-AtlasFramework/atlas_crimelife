-- atlas_crimelife / gangvault — config (data only).
-- Loaded server-side only. Keeps the gang-vault primitive
-- (deposit/withdraw/credit/debit) usable across atlas_mgmt's gang
-- menu, charterer NPC, archetype upgrades, etc. The racketeering /
-- protection income source that originally fed this vault has been
-- removed; what remains is a generic gang-shared markedbills balance
-- that stores in MongoDB collection `gang_vaults`.

GangVault = GangVault or {}

GangVault.Config = {
    -- Hard cap on a single gang's vault balance. Accepting markedbills
    -- past this amount silently drops the overflow (CreditGangVault
    -- returns the amount actually credited, post-cap).
    vaultCap = 75000,
}

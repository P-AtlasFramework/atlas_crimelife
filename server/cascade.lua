-- atlas_crimelife — character delete cascade.
--
-- Only one cross-character collection: `crime_runs` is the unified
-- audit log of who did what crime when. Audit-preserve so forensics
-- (and the future investigation board) can still trace history; live
-- queries by `citizenid` return nothing.
--
-- Other crimelife state:
--   gang_vaults    — keyed by gang, not citizenid. Member cleanup
--                    happens via atlas_mgmt's `gangs.members` array-pull.
--   vin_cloned     — by plate, not citizenid. Vehicle cascade handles.
--   vin_scratched  — by plate. Same.

local function archiveCharacterCrimelife(citizenid, reason)
    if type(citizenid) ~= 'string' or citizenid == '' then return end
    MongoDB.Game.updateMany('crime_runs',
        { citizenid = citizenid },
        { ['$set'] = { citizenid_archived = citizenid, citizenid = '__deleted__' } })
    print(('^2[atlas_crimelife] cascade: archived crime_runs for %s (%s)^0')
        :format(citizenid, reason or 'voluntary'))
end

AddEventHandler('atlas_core:characterDeleting', archiveCharacterCrimelife)

-- ─── Janitor: crime_runs retention ───────────────────────────────
-- 365 days. Long because the investigation board may want long-tail
-- forensics on an inactive citizenid.
exports['atlas_mongodb']:RegisterJanitor({
    name          = 'crime_runs_retention',
    collection    = 'crime_runs',
    intervalHours = 24,
    filter        = function()
        local cutoff = os.date('!%Y-%m-%dT%H:%M:%SZ', os.time() - 365 * 86400)
        return { timestamp = { ['$lt'] = cutoff } }
    end,
})

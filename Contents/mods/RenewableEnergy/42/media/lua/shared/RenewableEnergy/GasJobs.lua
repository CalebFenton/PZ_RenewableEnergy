-- The hands-on jobs at a digester, its gas heater, a gasifier and a generator's Gas Conversion Kit,
-- which RenewableEnergyGasAction does: what refuses one and what it takes, the same on every side,
-- so a menu greys out exactly what the authority refuses, and how the authority does one. Each
-- feature's job module holds its table of jobs and how to read its target, and GasJobs.define gives
-- it the rest; each feature's authority side says what its jobs do there, and GasJobs.perform does
-- them all in the same order.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Materials"

RenewableEnergy = RenewableEnergy or {}
local GasJobs = {}
RenewableEnergy.GasJobs = GasJobs

local Materials = RenewableEnergy.Materials

-- What refuses `character` doing `job` of `Jobs` at a target read as `subject`: a blocker first,
-- then what is wrong with `with`, then "short" for the first unmet need.
local function refusalAt(Jobs, character, job, subject, with)
    return Jobs.blocker(job, subject, with)
        or Jobs.check(character, job, subject, with)
        or (RenewableEnergy.firstUnmet(Jobs.needs(character, job, subject, with)) and "short")
        or nil
end

--- Gives the job module `Jobs` its functions. `Jobs.JOBS` has a row for each job:
--- - blocker(subject, with): the state of the target that refuses the job, as a translation key,
---   or nil. hideBlocked: a menu leaves the job out, rather than greyed, while its blocker refuses
---   it, as it belongs to another state of the target.
--- - check(character, subject, with), if any: what refuses `with`, what the character brings.
--- - materials: what it takes of the character (RenewableEnergy.Materials), or a
---   function(subject, with) of them.
--- - xp: { perk, amount }, what it gives once done.
--- - minutes, or a function(target, with) of them, and how it looks (RenewableEnergyGasAction).
--- `spec.subjectOf(target)`: what the rows read of the target worked at, or nil when there is none
--- to work at, which `spec.missing`, a translation key, says.
function GasJobs.define(Jobs, spec)
    Jobs.subjectOf = spec.subjectOf

    --- What `job` takes (RenewableEnergy.Materials).
    function Jobs.materials(job, subject, with)
        local materials = Jobs.JOBS[job].materials
        if type(materials) == "function" then
            return materials(subject, with)
        end
        return materials or {}
    end

    --- What `job` takes of `character`, as needs (RenewableEnergy.firstUnmet, RenewableEnergy.Needs).
    function Jobs.needs(character, job, subject, with)
        return Materials.needs(character, Jobs.materials(job, subject, with))
    end

    --- The state of the target that refuses `job`, as a translation key, or nil.
    function Jobs.blocker(job, subject, with)
        local blocker = Jobs.JOBS[job].blocker
        return blocker and blocker(subject, with) or nil
    end

    --- What refuses `with`, what `character` brings to `job`, as a translation key, or nil.
    function Jobs.check(character, job, subject, with)
        local check = Jobs.JOBS[job].check
        return check and check(character, subject, with) or nil
    end

    --- What refuses `character` doing `job` at `target` with `with`, as this side knows it now: a
    --- translation key, "short" when they lack a need, or nil.
    function Jobs.refusal(character, job, target, with)
        local subject = Jobs.JOBS[job] and target and spec.subjectOf(target)
        if not subject then
            return spec.missing
        end
        return refusalAt(Jobs, character, job, subject, with)
    end
end

--- Does `job` of the job module `Jobs` for `character` at `target`, with `with` what it works
--- with (RenewableEnergyGasAction), on the authority once its timed action finished. `site` is the
--- feature's side of its jobs there:
--- - open(target, with): brings what the jobs work on up to now and returns it, the `place`; nil
---   when there is none yet, as a generator's kit state before the kit.
--- - act(character, job, place, row, target, with): does the job, beyond what it takes and gives;
---   returns true when it was done.
--- - tell(place, target, done): shows and sends what changed.
--- In this order: catch up, so the time before counts at the old state; recheck the job as the
--- authority knows it now; read what it takes before doing it, since doing it can change that
--- (lighting a cold gasifier warms it, and a warm one takes no bellows); do it; only once it was
--- done take what it takes and give its row's XP, so a job not done costs and teaches nothing;
--- tell, done or not, since catching up changed it too. Returns whether it was done.
function GasJobs.perform(Jobs, site, character, job, target, with)
    local place = site.open(target, with)
    local row = Jobs.JOBS[job]
    local subject = row and Jobs.subjectOf(target)
    local done = false
    if subject and not refusalAt(Jobs, character, job, subject, with) then
        local materials = Jobs.materials(job, subject, with)
        done = site.act(character, job, place, row, target, with) == true
        if done then
            Materials.consume(character, materials)
            if row.xp then
                addXp(character, Perks[row.xp.perk], row.xp.amount)
            end
        end
    end
    site.tell(place, target, done)
    return done
end

return GasJobs

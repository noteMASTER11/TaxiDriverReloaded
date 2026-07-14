-- Passenger and driver identity data, isolated from runtime trip logic.
local M = {}

local firstNames = {
  "Aiden", "Alice", "Amelia", "Benjamin", "Charlotte", "Chloe", "Daniel", "Eleanor",
  "Emily", "Ethan", "Evelyn", "Grace", "Henry", "Isabella", "Jack", "James",
  "Liam", "Lily", "Lucas", "Mason", "Mia", "Noah", "Olivia", "Oscar",
  "Ruby", "Samuel", "Scarlett", "Sophia", "Thomas", "Victoria", "William", "Zoe"
}

local lastNames = {
  "Adams", "Baker", "Bennett", "Brooks", "Brown", "Campbell", "Carter", "Clark",
  "Collins", "Cooper", "Davis", "Edwards", "Evans", "Foster", "Green", "Hall",
  "Harris", "Hayes", "Hill", "Howard", "Jackson", "Johnson", "Lewis", "Martin",
  "Miller", "Mitchell", "Morgan", "Parker", "Reed", "Roberts", "Scott", "Walker"
}

M.driverAvatarOptions = {
  "🙂", "😊", "😎", "🤓", "🧑", "👨", "👩", "🧔",
  "👨‍🦰", "👩‍🦰", "👨‍🦱", "👩‍🦱", "👨‍🦳", "👩‍🦳", "🧑‍✈️", "🧑‍💼",
  "🧑‍🔧", "🦸", "🥷", "🤠", "🧢", "🎩", "🚕", "🏁",
  "🐻", "🦊", "🐼", "🐯", "🦁", "🐸", "🐵", "🐧"
}

M.driverAvatarSet = {}
for _, avatar in ipairs(M.driverAvatarOptions) do M.driverAvatarSet[avatar] = true end

function M.createPassengerName()
  return string.format(
    "%s %s",
    firstNames[math.random(#firstNames)],
    lastNames[math.random(#lastNames)]
  )
end

return M

local st = require "util.stanza";
local serpent = require("serpent")

function hasExpired(survey)
    if survey.expirationDate and type(survey.expirationDate) == "table" then
        if next(survey.expirationDate) then
            local today = os.time()
            local srvday = os.time(survey.expirationDate)
            if today > srvday then return true end
        end
    end
    return false
end

function loadSurveys()
    local file = io.open("surveys", "r")
    if file then
        local ok, res = serpent.load(file:read("*a"), {safe = false})
        file:close()
        if ok then
            for k, v in pairs(res) do
                if hasExpired(v) then
                    v.status = "closed"
                end
            end
            return res
        end
    end
    local surveys = {}
    return surveys
end

function storeSurveys(surveys)
    local file = io.open("surveys", "w")
    file:write(serpent.block(surveys))
    file:close()
end


local surveys = loadSurveys()

function riddim.plugins.survey(bot)
    bot:hook("commands/survey", function (command)
        local option = ""
        local unhandled = "Unhandled error"

		--Checks if there are arguments: !survey "arg1" "arg2" "..."
		if command.param then
            option = command.param:match('^(".-")') or command.param:match("^(.-) ") or command.param
        else
            return unhandled
        end
        local args = {}
        local replyStanza = st.reply(command.stanza);

        if option == "add" then
            for i in string.gmatch(command.param,'"(.-)"') do
                table.insert(args,i)
            end
            args = trimTable(args)
            local argsToSend = {}
            argsToSend.author = {jid = command.sender.real_jid:match("(.-)/"), nick = command.sender.nick}
            argsToSend.conference = command.sender.jid:match("(.-)/")
            if #args == 1 then
                argsToSend.question = args[1]
                table.insert(surveys,createSurvey(1, argsToSend))
            elseif #args == 2 then
                argsToSend.question = args[1]
                argsToSend.options = buildOptions(args[2])
                table.insert(surveys,createSurvey(2, argsToSend))
            elseif #args == 3 then
                argsToSend.question = args[1]
                argsToSend.options = buildOptions(args[2])
                argsToSend.expirationDate = createExpirationDate(args[3])
                table.insert(surveys,createSurvey(3, argsToSend))
            elseif #args == 4 then
            elseif #args == 5 then
            end
            storeSurveys(surveys)
        elseif option == "list" then
            local surveys = loadSurveys()
            for i in string.gmatch(command.param,'"(.-)"') do
                table.insert(args,i)
            end

			--return all surveys (from that conference)
			if args[1] == "all" then
                local surveysToPrint = ""
                for k, v in pairs(surveys) do
                    if v.conference == command.sender.jid:match("(.-)/") then
                        surveysToPrint = surveysToPrint .. v:toString("short") .. "\n-\t-\t-\t-\t-\t-\n"
                    end
                end
                command.room:send(replyStanza:body(surveysToPrint))

			-- return the specified survey
			elseif tonumber(args[1]) then
                local id = tonumber(args[1])
                for k, v in pairs(surveys) do
                    if v.conference == command.sender.jid:match("(.-)/") and id == v.id then
                        command.room:send(replyStanza:body(v:toString("short")))
                        break
                    end
                end
			--return the last survey
			else
                local survey = getLastSurvey(command.sender.jid:match("(.-)/"), surveys)
                if next(survey) ~= nil then
                    command.room:send(replyStanza:body(survey:toString("short")))
                else
                    return unhandled
                end
            end
		--if !survey 2 → answer nº 2 to the last survey
		--if !survey 2 1 → answer nº1 to the survey with id 2
		elseif tonumber(option) then
            local surveys = loadSurveys()
            for i in string.gmatch(command.param,'"(.-)"') do
                table.insert(args,i)
            end
            local user = {jid = command.sender.real_jid:match("(.-)/"), nick = command.sender.nick, conference = command.sender.jid:match("(.-)/")}

            if #args == 1 then
                local survey = getSurveyById(tonumber(option), user.conference, surveys)
                if survey ~= nil then
                    if next(survey) and survey.status == "open" then
                        if not hasVoted(user, survey) then
                            local vote = {}
                            vote.user = user
                            vote.date = os.date("!*t", os.time())
                            if type(survey.options) == "table" then
                                local opt = survey.options[tonumber(args[1])]
                                if opt then
                                    vote.option = shallowcopy(survey.options[tonumber(args[1])])
                                else
                                    return "Invalid option"
                                end
                            else
                                vote.option = args[1]
                            end
                            table.insert(survey.votes,vote)
                        else
                            return "You have already voted in this survey"
                        end
                    else
                        return "This survey is " .. survey.status
                    end
                else
                    return "Survey does not exist"
                end
			--!survey number (voting in the last survey (number is one of the possible answers))
			else
                local survey = getLastSurvey(command.sender.jid:match("(.-)/"), surveys)
                if next(survey) and survey.status == "open" then
                    if not hasVoted(user, survey) then
                        local vote = {}
                        vote.user = user
                        vote.option = shallowcopy(survey.options[tonumber(option)])
                        vote.date = os.date("!*t", os.time())
                        table.insert(survey.votes, vote)
                    else
                        return "You have already voted in this survey"
                    end
                else
                    return "This survey is " .. survey.status
                end
            end
            storeSurveys(surveys)
		--!survey "my opinion" (voting in the last open-question survey)
		elseif option:match('^"(.-)"') then
            local surveys = loadSurveys()
            local user = {jid = command.sender.real_jid:match("(.-)/"), nick = command.sender.nick, conference = command.sender.jid:match("(.-)/")}
            local survey = getLastSurvey(command.sender.jid:match("(.-)/"), surveys)
            if next(survey) and survey.status == "open" then
                if not hasVoted(user, survey) then
                    if type(survey.options) ~= "table" then
                        local vote = {}
                        vote.user = user
                        vote.option = option:match('^"(.-)"')
                        vote.date = os.date("!*t", os.time())
                        table.insert(survey.votes, vote)
                    else
                        return "Please, choose an answer"
                    end
                else
                    return "You have already voted in this survey"
                end
            else
                return "This survey is " .. survey.status
            end
            storeSurveys(surveys)
        else
            return unhandled
        end

    end);
end

function getSurveyById(id, conference, surveys)
    if next(surveys) then
        for k, v in pairs(surveys) do
            if v.id == id and v.conference == conference then
                return v
            end
        end
    end
    return nil
end

function hasVoted(user,survey)
    if next(survey.votes) then
        for k, v in pairs(survey.votes) do
            if v.user.jid == user.jid then
                return true
            end
        end
    end
    return false
end

function getLastSurvey(conference, surveys)
    local srvs = {}
    local srv = {}
    for k, v in pairs(surveys) do
        if v.conference == conference then
            table.insert(srvs,v)
        end
    end
    srv = srvs[1] or {}
    for k, v in pairs(srvs) do
        if os.time(v.creationDate) > os.time(srv.creationDate) then
            srv = v
        end
    end

    return srv
end

function createExpirationDate(arg)
    if type(arg) == "string" then
        local seconds = 0
        for i in string.gmatch(arg, "%d%d?%d?[hmd]") do
			--convert days into seconds -- take only 30/31 days
			if i:match("%d%d?%d?d") then
                local days = tonumber(i:match("(%d%d?%d?)"))
                if days > 31 then
                    days = 31
                end
                seconds = seconds + (days * 86400)
			--convert hours into seconds -- take only 23 hours
			elseif i:match("%d%d?%d?h") then 
                local hours = tonumber(i:match("(%d%d?%d?)"))
                if hours > 23 then
                    hours = 23
                end
                seconds = seconds + (hours * 3600)
			--convert minutes into seconds -- take only 59 minutes
			elseif i:match("%d%d?%d?m") then
                local minutes = tonumber(i:match("(%d%d?%d?)"))
                if minutes > 59 then
                    minutes = 59
                end
                seconds = seconds + (minutes * 60)
            end
        end
        seconds = seconds + os.time()
        return os.date("!*t", seconds)
    end

    return 0
end

function trimTable(t)
    for k,v in ipairs(t) do
        if type(v) == "string" then
            t[k] = v:match("^%s*(.-)%s*$")
        end
	end
	return t
end

function buildOptions(str)
    local str = str .. ","
    local options = {}
    for i in string.gmatch(str,"(.-),") do
        if string.find(i,"%a") then
            local option = {}
            option.text = i:match("^%s*(.-)%s*$")
            table.insert(options,option)
            options[option.text] = option
        end
    end
    if #options < 2 then
        options = 0
    end
    return options
end

function createSurvey(kind, args)

    local emptySurvey = {
        question = "",
        author = {jid = "", nick = ""},
        conference = "",
        options = 0,
        creationDate = os.date("!*t",os.time()),
        expirationDate = 0,
        allowedVotes = 0,
        allowedPeople = 0,
        status = "open",
        votes = {},
        id = #surveys + 1,
		-- Use set metamethod __tostring instead of a function
		toString = function (self, mode) --long or short. Long: Vote + nick | short: vote.
            local options = "any"
            local date = "Expires: never"
            local votes = "0 votes."
            local chart = {}
            if type(self.options) == "table" then
                options = "|"
				for k, v in pairs(self.options) do
                    if v ~= nil then
                        options = options .. v.text .. "|"
                        chart[v.text] = "0"
                	end
                end
            end
            if type(self.expirationDate) == "table" then
                date = os.date("%d/%m/%y %X", os.time(self.expirationDate))
            end

            if next(self.votes) and type(self.options) == "table" then
                votes = ""
                for _, vote in pairs(self.votes) do
                    if vote.option then
                        if vote.option.text then
                            chart[vote.option.text] = chart[vote.option.text] +1
                        end
                    end
                end

                for k, v in pairs(chart) do
                    votes = votes .. k .. ": " .. v .. "| "
                end

            elseif next(self.votes) then
                votes = "\nAnswers:\n"
                for k, v in pairs(self.votes) do
                    votes = votes .. v.option .."\tBy: " .. v.user.nick .."\n"
                end
            end

            if mode == "long" then
                return self.question .. "\tID: " .. self.id  .. "\nPossible answers: " .. options .. "\nExpires: " .. date .. "\nVotes: " .. votes .. "\nBy: " .. self.author.nick
            elseif mode == "short" then
                return "ID: " .. self.id .. "\t".. self.question .."\t" .. options .. "\t" .. date .. "\t" .. votes .. "\tBy: " .. self.author.nick
            end

        end
    }
	local survey = emptySurvey
	survey.author = args.author
	survey.conference = args.conference
	if kind == 1 then
		survey.question = args.question
	elseif kind == 2 then
		survey.question = args.question
		survey.options = args.options
	elseif kind == 3 then
		survey.question = args.question
		survey.options = args.options
		survey.expirationDate = args.expirationDate
	elseif kind == 4 then
		survey.question = args.question
		survey.options = args.options
		survey.expirationDate = args.expirationDate
		survey.allowedVotes = args.allowedVotes
	elseif kind == 5 then
		survey.question = args.question
		survey.options = args.options
		survey.expirationDate = args.expirationDate
		survey.allowedVotes = args.allowedVotes
		survey.allowedPeople = args.allowedPeople
	end

	if kind >= 1 and kind <= 5 then
		return survey
	end

end

function shallowcopy(orig) --Utility to copy tables
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else
        copy = orig
    end
    return copy
end


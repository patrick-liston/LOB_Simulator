## AGENTS



########################################################
#######            AGENT STRATEGIES              ######
########################################################

## Trend Agent - 
    #Find if the price is going up or down
    #If the FIRST price is less than the LAST price - SELL
function Trend_Calc(trade_prices::Vector{Float64}, agent_params::Vector)
    try
        if trade_prices[length(trade_prices)-agent_params[2]] < last(trade_prices)
            return 0 #SELL
        else
            return 1 #BUY
        end
    catch
    print("Not enough history - Chosing randomly")
    return rand(Bool,1,1)[1]
    end
end

## Mean Rverting agent 
    #Find if the price is above/below the Average
    #If the MEAN price is less than the LAST price -
function Mean_Calc(trade_prices::Vector{Float64}, agent_params::Vector)
    try
    if mean(last(trade_prices,agent_params[2])) < last(trade_prices)
        return 1 #BUY
    else
        return 0 #SELL
    end
    catch
        print("Not enough history - Chosing randomly")
        return rand(Bool,1,1)[1]
    end
end

# Spike agent will trade in the direction of the side with the most stop-loss orders
function Spike_Agent(sl_buys, sl_sells)
    sl_buys_amount = getindex.(sl_buys,2)
    sl_sells_amount = getindex.(sl_sells,2)
    return ifelse(sl_buys_amount>sl_sells_amount, true, false)
end
    



########################################################
#######           GENERATING ACCOUNTS             ######
########################################################
function generate_accounts(accounts::Vector, num_agents::Int, starting_shares::Float64, starting_cash::Float64, agent_params::Vector)
    start_agent=ifelse(length(accounts)>0,length(accounts), 0)
    for agent in start_agent+1:start_agent+num_agents
        push!(accounts, [agent, starting_shares, starting_cash, deepcopy(agent_params)])  #Deepcopy required so that when we update the list for each agent, it doesn't proliferate through all agents. i.e Need different pointer addresses for each agent.
    end
    return accounts
end


########################################################
#######           AGENT SELCTION               ######
########################################################
#Function to select the correct agent behaviour 
function select_agent_calc_method(agent_strat::String, agent_params::Vector)
    if agent_strat=="R"
        real_trade_direction=rand(Bool,1,1)[1]
    elseif agent_strat=="Markov"
        real_trade_direction=Markov_Calc(previous_direction)
    elseif agent_strat=="T"
        real_trade_direction=Trend_Calc(tracking_in.trade_prices, agent_params)
    elseif agent_strat=="M"
        real_trade_direction=Mean_Calc(tracking_in.trade_prices, agent_params)
    
    
    elseif agent_strat=="S"
        #Want to make the spike direction consistent - just spike it upward for now
        #real_trade_direction=Spike_Agent(sl_buys, sl_sells)
        if agent_params[3]==1  && buy_back_strategy==2 #This is the FIRST order for strat 2
            real_trade_direction = ifelse(agent_params[2]=="UP", 0, 1)
        elseif agent_params[3]==10  && buy_back_strategy==3 #This is the FIRST order for strat 3
            real_trade_direction = ifelse(agent_params[2]=="UP", 0, 1)
        elseif agent_params[3]==0  && buy_back_strategy==1 #This is the FIRST order for strat 1
            real_trade_direction = ifelse(agent_params[2]=="UP", 0, 1)
        else    #If we need to place opposing orders - to buy back
            print("\nActivating FInal Buy Back")
            real_trade_direction = ifelse(agent_params[2]=="UP", 1, 0)
            # sleep(5)
        end
        
        print("\nDid Spike agent strat: ", real_trade_direction)
        print("\n\n\n\nSPIKE DIRECTION!", agent_params[2])

    else
        print("This strategy hasn't been written yet: ", agent_strat)
        real_trade_direction=0
    end
    return  real_trade_direction
end

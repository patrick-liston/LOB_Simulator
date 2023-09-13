#Compact execution
########################################################
########################################################
#######          BUY/SELL FUNCTIONS               ######
########################################################
########################################################
#Buy and Sell functions - with LOB extrapolation

####    Method to execute a buy order   ####
        # price, pos, cash_amount, traded_amount, accounts, executed_trade = buy_order(accounts, prices, amounts, agent_id, trade_size)
        # price, pos, cash_amount, traded_amount, accounts, executed_trade = sell_order(accounts, prices, amounts, agent_id, trade_size)

##### Main BUY order execution - this is the function that gets called in the script 
##############################################################################
#######   MAIN buy_order function - handles execution & placement   ######
##############################################################################
function buy_order(accounts::Vector, prices::Vector{Float64}, amounts::Vector{Float64}, agent_id::Int64, trade_size::Float64, trackin_in)
    cash_amount = 0; traded_amount=0; pos = 1 #First bid
    cash_remaining = accounts[agent_id][3]
    amounts = amounts[21:40]; prices = prices[21:40]
    #If we don't have enough cash do NOT execute - and just exit
    if cash_remaining<1 && abs(prices[1])>0.2
        return prices[pos], pos, cash_remaining, cash_amount, traded_amount, false
    end

    #Buy execution - real LOB
    price, pos, cash_remaining, cash_amount, traded_amount = buy_order_ex(cash_remaining, traded_amount, trade_size, 1, amounts, prices, cash_amount)

    ##### Extend out the LOB where appropriate  ####
    while traded_amount<trade_size*0.999  && cash_remaining>1 #If not fully executed (within params) then do the execution stuff again
#        print("\nExtrapolating BUY book!\n")
        #Extend and sell
        amounts, prices = extrapolate_lob(model_path, tracking_in, last(amounts, 20), last(prices, 20), true  ) #Hard-code the trade direction 0-Sell :. look at Asks
        #Excute the Buy again
        price, pos, cash_remaining, cash_amount, traded_amount = buy_order_ex(cash_remaining, traded_amount, trade_size, pos, amounts, prices, cash_amount)
    end   #End extension execution
    #Update Accounts and return infor
    update_account_holdings(accounts, agent_id, traded_amount, -cash_amount) #Update accounts position. NOTE: BUY, ∴ negative cash_amount (to decrease cash)   
    #print("\nAccounts stuff", accounts[1], " len: ", length(accounts))
    return price, pos, cash_amount, traded_amount, accounts,  true , trackin_in#Use this to update the price, and then log the amounts of stuff, and update the agents holdings
end
########################################################
#######       BUY: LOOP TO EXECUTE TRADE        ######
########################################################
function buy_order_ex(cash_remaining, traded_amount, trade_size, initial_pos::Int, amounts::Vector{Float64}, prices::Vector{Float64}, cash_amount)
    max_pos = length(amounts); pos=1
    while cash_remaining>0  && traded_amount<trade_size && pos<=max_pos #While the agent still has cash
        max_trade_size = trade_size-traded_amount  #Maximum allowed trade - need this because after the first iteration the trade_size is no longer the limiting factor.
        trade_amount=ifelse(amounts[pos]<=max_trade_size, amounts[pos], max_trade_size  )  #If the agent can afford full LOB amount - - otherwise, only do the amount we can trade
        trade_amount = ifelse(cash_remaining/prices[pos]>trade_amount, trade_amount, cash_remaining/prices[pos]) #If there is more cash remaining THAN trade_amount, then max_trade is determined by trade_amount.

        traded_amount+=trade_amount        
        cash_remaining-=trade_amount*prices[pos] #Cash value of trade at this lob level
        cash_amount+=trade_amount*prices[pos] #Cash value of trade at this lob level
        pos += ifelse(trade_amount==amounts[pos], 1, 0) #Ensure we only "skip-up" a level if we have filled all orders at this level
    end
    pos = ifelse(pos<=max_pos, pos, max_pos) #Ensure we don't go over the positional limit
    return prices[pos], initial_pos+pos-1, cash_remaining, cash_amount, traded_amount
end


##############################################################################
#######   MAIN sell_order function - handles execution & placement   ######
##############################################################################
function sell_order(accounts::Vector, prices::Vector{Float64}, amounts::Vector{Float64}, agent_id::Int64, trade_size::Float64, trackin_in)
    cash_amount = 0.0; traded_amount = 0.0; pos = 1 #First bid
    trade_size = ifelse(accounts[agent_id][2]>trade_size, trade_size, accounts[agent_id][2] )#Check the agent can make this trade - If do NOT have enough stock - adjust it down               
    prices = prices[1:20]; amounts = amounts[1:20]
    #Initial trade - with normal LOB book
    price, pos, cash_amount, traded_amount = sell_order_ex(prices, amounts, trade_size, 1, cash_amount, traded_amount)

    ### DO ALL THE OTHER EXTRAPOLATION AND EXECUTION STUFF ###
    ##### Extend out the LOB where appropriate 
    while traded_amount<trade_size*0.999 #If not fully executed (within params) then do the execution stuff again
 #       print("\nExtrapolating SELL book!\n")
        #Extend and sell
        amounts, prices = extrapolate_lob(model_path, tracking_in, last(amounts, 20), last(prices, 20), false  ) #Hard-code the trade direction 0-Sell :. look at Asks
        #Excute the sell again
        price, pos, cash_amount, traded_amount = sell_order_ex(prices, amounts, trade_size, pos, cash_amount, traded_amount)
    end

    #Final account update
    accounts = update_account_holdings(accounts, agent_id, -traded_amount, cash_amount) #Update accounts position. NOTE: SELL, ∴ negative trade_amount (to decrease shares)   
    trade_executed = ifelse(traded_amount>0.000001, true, false)
    return price, pos, cash_amount, traded_amount, accounts, trade_executed, trackin_in
end


########################################################
#######       BUY: LOOP TO EXECUTE TRADE        ######
########################################################
function sell_order_ex(prices::Vector{Float64}, amounts::Vector{Float64}, trade_size::Float64, initial_pos::Int64, cash_amount::Float64, traded_amount::Float64)
    max_pos = length(prices); pos=1
    while traded_amount<trade_size && pos<max_pos #&& available_shares>0 #available_cash>0 #Last condition ensure we do not go below ZERO
        max_trade_size = trade_size-traded_amount  #Maximum allowed trade - need this because after the first iteration the trade_size is no longer the limiting factor.
        trade_amount=ifelse(amounts[pos]<=max_trade_size, amounts[pos], max_trade_size  )  #If the agent can afford full LOB amount - - otherwise, only do the amount we can trade
        
        traded_amount+=trade_amount
        cash_amount+=trade_amount*prices[pos]
        pos += ifelse(trade_amount==amounts[pos], 1, 0) #Ensure we only "skip-up" a level if we have filled all orders at this level
    end
    pos = ifelse(pos<=max_pos, pos, max_pos)  #Ensure we don't go over the positional limit
    return prices[pos], initial_pos+pos-1, cash_amount, traded_amount #Use this to update the price, and then log the amounts of stuff, and update the agents holdings
end






# include("/home/patrick/Desktop/PhD/AAMAS_2023/Simulator_Scripts/LOB_Extrapolation.jl")
# include("/home/patrick/Desktop/PhD/AAMAS_2023/Simulator_Scripts/Buy_Sell_Order_Execution.jl")
# include("/home/patrick/Desktop/PhD/AAMAS_2023/Simulator_Scripts/Everything_Needed_to_Run_Sim.jl")
# include("/home/patrick/Desktop/PhD/AAMAS_2023/Simulator_Scripts/Data_Pre_Post_Process.jl")
# include("/home/patrick/Desktop/PhD/AAMAS_2023/Simulator_Scripts/Agents.jl")
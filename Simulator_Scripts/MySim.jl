#FIX UP SPIKE ONE

possible_exps=[
[0, 1, 1, "UP", 1],
[0, 1, 1, "DOWN", 1],
[0, 1, 0, "None",1],
] 


#Fix accounts
#https://quantpy.com.au/risk-management/value-at-risk-var-and-conditional-var-cvar/
using PyCall
using CSV
using Random
using DataFrames
using ProgressBars
using BenchmarkTools
using DelimitedFiles
using StatsBase
using Dates
using JDF

#Bring in the LOB extrapolation and Order execution functions 
include("/home/patrick/Desktop/PhD/SL_LOB_Extrapolation_Hybrid_Spikes/LOB_Extrapolation.jl")
include("/home/patrick/Desktop/PhD/SL_LOB_Extrapolation_Hybrid_Spikes/Buy_Sell_Order_Execution.jl")
include("/home/patrick/Desktop/PhD/SL_LOB_Extrapolation_Hybrid_Spikes/Everything_Needed_to_Run_Sim.jl")

save_stuff = 0
new_sim = 1
stop_loss_order = 1
spiked = 0
#spike_direcion="UP"
save_data=0
total_sim_time=100_000
seed_num=rand(1:10000)
tracking_in = tracking([], [], [], [], [], [], [], [], [], [], [], [], [] )

combos= [[1,1], [1,0], [0,1], [0,0]] #Spike vs No Spike, SL vs No-SL


date="20"
path="/home/patrick/Desktop/"
model_path = "/home/patrick/Desktop/PhD/LOB_Download/Models"
if new_sim==1
    read_in_lob= CSV.read(path*"/BTCUSDT_S_DEPTH/BTCUSDT_S_DEPTH_202111"*date*".csv", DataFrame)#, limit=2000000)
    read_in_data=CSV.read(path*"/BTCUSDT_TRADES/BTCUSDT-trades-2021-11-"*date*".csv", DataFrame)#, limit=2000000)
    #read_in_real_qtys= readdlm("/home/patrick/Desktop/PhD/Qtys.csv", ',', Float64)
    read_in_real_qtys=CSV.read("/home/patrick/Desktop/PhD/Qtys.csv", DataFrame)
    read_in_real_qtys = vec(read_in_real_qtys[:qty])
end


#Mean and STD used to calculate the size of the orders' stop-loss. (Intention to use the amount to find a Z-score which is then the %added/subtracted to the current price. Resulting in the stop-loss trigger price.)
μ = mean(read_in_real_qtys)
σ = std(read_in_real_qtys)
for num_sims in range(1 , length=2)  #Number of simulations to run
    print("\n\n\n\nRunning simulation number: ", num_sims, "\n\n\n\n\n")
    seeds= readdlm("/home/patrick/Desktop/PhD/ICAIF_2023/seeds.csv", ',', Int, '\n')[6:end]
    seed_num=seeds[num_sims]
    Random.seed!(seed_num)

     

for combo in range(1, length=length(possible_exps))   #COmbination of setting, spiked/un-spiked, sl/non-sl
#stop_loss_order, spiked = combo[1], combo[2]
random_only = possible_exps[combo][1]
stop_loss_order= possible_exps[combo][2]
spiked = possible_exps[combo][3]
spike_direction = possible_exps[combo][4]
buy_back_strategy = possible_exps[combo][5]

print("Random only: ", random_only, "  Stop Losses: ", stop_loss_order, "  Spiked: ", spiked, 
"  Direction: ", spike_direction, "   Buy back method :", buy_back_strategy, "\n\n\n\n")


############################
# TRIAL STUFF
############################
print("\nTrial Number ")
trial_num=seed_num
print(trial_num)

df=[]
stop_orders_to_execute=[]


print("\nCopying Data... ")
real_qtys=copy(first(read_in_real_qtys,total_sim_time*3))
data=copy(first(read_in_data,total_sim_time*3))
rename!(data,[:trade_Id,:price,:qty,:quoteQty,:time,:isBuyerMaker])
lob=copy(first(read_in_lob,total_sim_time*3))
print("\nRead in all data.")


spike_increment=1_000
### DOING TIMING STUFF  ###
start_time=first(data.time)
end_time=data.time[total_sim_time]
times_to_sim=first(data.time,total_sim_time)
real_trade_directions=first(data.isBuyerMaker,total_sim_time)
real_prices=first(data.price,total_sim_time)
spike_time =  times_to_sim[Int(total_sim_time/2)]   
spike_buy_back_time = times_to_sim[Int(total_sim_time/2 + spike_increment)]    







########################################################
#######             SET AGENT LIMITS              ######
########################################################
num_agents=10_000; starting_shares=100.015 ; starting_cash=5_000_000.00
agent_params=["R", 0.5, 0]
accounts=[]
accounts=generate_accounts(accounts, num_agents, starting_shares, starting_cash, agent_params)

if random_only==0 #If we're allowed various types - then make these
#num_agents=100; starting_shares=10000.015 ; starting_cash=100050000000.00
num_agents=1_000; starting_shares=100.015 ; starting_cash=5_000_000.00
agent_params=["T", 50, 0]
accounts=generate_accounts(accounts, num_agents, starting_shares, starting_cash, agent_params)

num_agents=1_000; starting_shares=100.015 ; starting_cash=5_000_000.00
agent_params=["M", 50, 0]
accounts=generate_accounts(accounts, num_agents, starting_shares, starting_cash, agent_params)

num_agents=1; spike_starting_shares=1_000_00_000.015 ; spike_starting_cash=5_000_000_000_000.00
agent_params=["S", spike_direction, 0]  #Spike agent
accounts=generate_accounts(accounts, num_agents, spike_starting_shares, spike_starting_cash, agent_params)
end #Only allowed other types sometimes
##### Include at least on RL agent? ####

number_of_agents_in_simulation=length(accounts)
print("\nLength of accounts: ", number_of_agents_in_simulation)

#

#Need this to determine what each strategy will do  - trade_prices
# Selects an agent at random


#Select the right method for value/Direction calculation
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


########################################################
#######          SPACE FOR AGENT TYPES            ######
########################################################
function update_order_book(lob::DataFrame, current_time::Int, price::Float64)
    lob_now, lob = import_orderbook(current_time, lob) #Import the LOB for the closest time
    prices = get_prices(lob_now::DataFrameRow) #Order prices
    amounts = get_volumns(lob_now::DataFrameRow) #Order amounts/size/volume
    prices = shift_lob(price, prices) #Shift "prices" to the "correct" level
    return prices, amounts, lob
end



function run_sim_step(previous_time, current_time, price,  real_qtys, accounts, tracking_in, lob, prices, amounts)
    #If we have moved a time-step. Update the LOB
    if previous_time != current_time
        prices, amounts, lob = update_order_book(lob, current_time, price)
    end

    #DETERMINE IF WE ARE SPIKING NOW - IF SPIKE, SELECT THE SPIKE AGENT AND TRADE SIZE, ELSE RANDOM AGENT AND RANDOM SIZE
    if current_time == spike_time && spiked==1
        agent_id = length(agents)+1
        trade_size = maximum(read_in_real_qtys) * 2 #1_000
        # prices, amounts, lob = update_order_book(lob, current_time, price)
        # Selects an agent at random
        print("\n\nSHould have a spike\n\n\n")
        print("Agent STrat: ", accounts[agent_id][4][1])
    else
        agent_id=get_trading_agent(agents)
        trade_size = get_trade_size(real_qtys)
    end

    agent_strat=accounts[agent_id][4][1]
    agent_params=accounts[agent_id][4]
    trade_direction = select_agent_calc_method(agent_strat, agent_params)


    order = [agent_id, trade_direction, trade_size, 0, current_time]
    #price, traded_amount, cash_amount, pos, accounts = proper_trade(accounts, prices, amounts, trade_direction, agent_id, trade_size)
    price, traded_amount, cash_amount, pos, accounts = simple_trade(accounts, prices, amounts, order, tracking_in)
    # try
    #     price, traded_amount, cash_amount, pos, accounts = simple_trade(accounts, prices, amounts, order, tracking_in)
    # catch
    #     print("\n\n\n\n\n\nBig problem here")
    # end
    
    #tracking_in =  tracking_info(tracking_in, prices, traded_amount, cash_amount, pos, trade_direction, current_time, "N", agent_strat)
    return  current_time, price,  accounts, tracking_in, lob, prices, amounts
end # End simulation step function





function run_sim_step_sl(previous_time, current_time, price,  real_qtys, accounts, tracking_in, lob, prices, amounts, sl_sells, sl_buys, μ, σ, spike_buy_back_time, n)
    #If we have moved a time-step. Update the LOB
    if previous_time != current_time
        prices, amounts, lob = update_order_book(lob, current_time, price)
    end 
#DETERMINE IF WE ARE SPIKING NOW - IF SPIKE, SELECT THE SPIKE AGENT AND TRADE SIZE, ELSE RANDOM AGENT AND RANDOM SIZE
    if current_time == spike_time && spiked==1 && accounts[length(agents)+1][4][3]==0
        agent_id = length(agents)+1
        trade_size = maximum(read_in_real_qtys) * 2 #1_000
        # prices, amounts, lob = update_order_book(lob, current_time, price)
        # Selects an agent at random
        print("\n\nSHould have a spike\n\n\n")
        print("Agent STrat: ", accounts[agent_id][4][1])
        print("\nSPike agent first trade size Trade size will be: ", trade_size)
        if buy_back_strategy==2
            accounts[agent_id][4][3]=1
            print("\nUpddating the buy back instructions: ", accounts[agent_id][4][3], " ", buy_back_strategy)
            print("active at:, ", spike_buy_back_time)
            print("\n\n\n")
        elseif buy_back_strategy==3
            accounts[agent_id][4][3]=10
            print("\nUpddating the buy back instructions: ", accounts[agent_id][4][3], " ", buy_back_strategy)
            print("active at:, ", spike_buy_back_time)
            print("\n\n\n")
        else
            accounts[agent_id][4][3]=0
        end
    elseif current_time == spike_buy_back_time && spiked==1 && accounts[length(agents)+1][4][3]>0
        agent_id = length(agents)+1
        print("\nStarting shares: ", 1_000_00_000.015)
        print("\nPre-Buy back  shares: ", accounts[agent_id][2])
        print("\nNumber of buy backs: ", accounts[agent_id][4][3])
        trade_size = abs((1_000_00_000.015 - accounts[agent_id][2])/accounts[agent_id][4][3])
        # prices, amounts, lob = update_order_book(lob, current_time, price)
        # Selects an agent at random
        print("\n\nSHould have a spike\n\n\n")
        print("\nAgent STrat: ", accounts[agent_id][4][1])
        print("\nAgent remaning triggers: ", accounts[agent_id][4][3])
        print("\nTrade size will be: ", trade_size)

        print("\n\n\n")
        accounts[agent_id][4][3]-=1
        print("\nAfter fixing the trigger! ", accounts[agent_id][4][3])
        # current_time +  (length(times_to_sim) - (length(times_to_sim)/2+spike_increment) ) /  4 #accounts[agent_id][4][3]
        # n +  (length(times_to_sim) - (length(times_to_sim)/2+spike_increment) ) /  4 #accounts[agent_id][4][3]
        # *length(times_to_sim)

        required_trades = ifelse(accounts[agent_id][4][3]>0,  (length(times_to_sim) - n) / accounts[agent_id][4][3], 0 ) #Avoid divide by zero error
        use_increment = minimum([required_trades, spike_increment])
        spike_buy_back_time = times_to_sim[Int(round(n+use_increment))]    

        
        print("\nWe're doing a BUY BACK: ", accounts[agent_id][4][3], " ", buy_back_strategy)
            print("\nCUrrent time: ", current_time)
            print("\nNext buy back  time: ", spike_buy_back_time)
            print("\nactive at:, ", spike_buy_back_time)
            print("\n\n\n")
            print("\n\nTime:", (unix2datetime.(current_time ./ 1000)))
            print("\nAccount of strat agent", last(accounts))
            
    else
        agent_id=get_trading_agent(agents)
        trade_size = get_trade_size(real_qtys)
    end


    agent_strat=accounts[agent_id][4][1]
    agent_params=accounts[agent_id][4]
    trade_direction = select_agent_calc_method(agent_strat, agent_params)


    
    order = [agent_id, trade_direction, trade_size, 0, current_time]
    # price, traded_amount, cash_amount, pos, accounts, sl_sells, 
    #                     sl_buys = proper_trade(accounts, prices, amounts, order,tracking_in, sl_sells, sl_buys, μ, σ)
    #print("\nOrder input for proper trade: \n",accounts, prices, amounts, order,tracking_in, sl_sells, sl_buys, μ, σ )
    #price, traded_amount, cash_amount, pos, accounts = proper_trade(accounts, prices, amounts, trade_direction, agent_id, trade_size)
    # price, traded_amount, cash_amount, pos, accounts, sl_sells, 
    #                     sl_buys = proper_trade(accounts, prices, amounts, order,tracking_in, sl_sells, sl_buys, μ, σ)
    try
        price, traded_amount, cash_amount, pos, accounts, sl_sells, 
                        sl_buys = proper_trade(accounts, prices, amounts, order,tracking_in, sl_sells, sl_buys, μ, σ)
    catch
        print("\n\n\n\n\n\nBig problem here")
    end
    #tracking_in =  tracking_info(tracking_in, prices, traded_amount, cash_amount, pos, trade_direction, current_time, "N", agent_strat)
    if agent_strat=="S";         print("\n\nFINISHED SPIKE AGENT TRADE \n\n", current_time); print("\nDid the spike\n"); end

    # if agent_strat=="S";         
    #     print("\n\nFINISHED SPIKE AGENT TRADE \n\n", current_time); 
    #     print("\n\nTime:", (unix2datetime.(current_time ./ 1000))); 
    #      if accounts[length(agents)+1][4][3]==0; 
    #         print("\nAccount stuff", last(accounts))
    #         stop ;end; end
    #tracking_in =  tracking_info(tracking_in, prices, traded_amount, cash_amount, pos, trade_direction, current_time, "N", agent_strat)
    return  current_time, price,  accounts, tracking_in, lob, prices, amounts, sl_sells, sl_buys, spike_buy_back_time
end # End simulation step function


########################################################
#######               Set Up STUFF               ######
########################################################

previous_time=0
trade_prices=[first(data[!,:price])]
price=data.price[findnearest(data.time,start_time)[1]]   #This should be the first trade price from BTCUSDT
#agents = [i for i in range(1, length = length(accounts))]
#If we allow a spike agent - count all agents, else only the non-spike agents
#agents = ifelse(spiked==1 ,  [i for i in range(1, length = length(accounts))],  [i for i in range(1, length = length(accounts)-1)])
agents = [i for i in range(1, length = length(accounts)-1)]


previous_price=price
lob_now, lob = import_orderbook(start_time, lob)

#previous_direction=real_trade_directions[index]
print("\nStarting simulation\n")
########################################################
#######               MAIN SIMULATION            ######
########################################################
#tracking_in = tracking_6([], [], [], [], [], [], [], [], [], [], [], [], [] )
tracking_in = tracking([], [], [], [], [], [], [], [], [], [], [], [], [] )
sl_sells = []
sl_buys = []

prices, amounts, lob = update_order_book(lob, first(times_to_sim), price)

if stop_loss_order==1 #Picking which simulator to use
total_time=range(1,length=length(times_to_sim))
for n in ProgressBar(total_time)
    current_time=times_to_sim[n]


    
    previous_time, price,  accounts, tracking_in, lob, prices, amounts, 
            sl_sells, sl_buys, spike_buy_back_time = run_sim_step_sl(previous_time, current_time, price,  
                                real_qtys, accounts, tracking_in, lob, prices, amounts, sl_sells, sl_buys, μ, σ, spike_buy_back_time, n )

end

#SPike agent is design to get rid of all SL orders. Thus must cause a huge spike. 
#Given there may be a gap between LOB shift and SL order prices, we need to recursively shift the LOB until it reaches the SL
#OR 
#Move the SL orders to the end of the LOB? 


else

total_time=range(1,length=length(times_to_sim))
for n in ProgressBar(total_time)
    current_time=times_to_sim[n]

    previous_time, price,  accounts, tracking_in, lob,
     prices, amounts = run_sim_step(previous_time, current_time, price,  
                                real_qtys, accounts, tracking_in, lob, prices, amounts )

end

end #Picking which simulator to use



print("Finished Simulation")


print("\n\n\nWe COULD start plotting now - if everything went well")





########################################################
#######           SAVING DATAFRAMES               ######
########################################################
using DataFrames
using CSV

df = DataFrame(time=tracking_in.simmed_times, price = tracking_in.trade_prices , max_price = tracking_in.max_buys,
min_price=tracking_in.max_sells, amount_traded=tracking_in.trade_amounts, trade_value=tracking_in.trade_cashes,
direction=tracking_in.trade_directions, lob_depth=tracking_in.LOB_depth_hit, stop_loss_order=tracking_in.stop_loss_order, agent_type=tracking_in.agent_type)
#print(first(df,7))

#print(last(df,7))
print("\nMax lob depth hit: ", maximum(tracking_in.LOB_depth_hit))


using Dates


last_time=last(first(data.time,total_sim_time))
times_plot= unix2datetime.(first(data.time,total_sim_time) ./ 1000)
last_simulated_time=findnearest(df.time,last_time)[1]
sim_times_plot=unix2datetime.(first(df.time,last_simulated_time) ./ 1000)
#last_stop_time=findnearest(df_stops.time,last_time)[1]
#stop_dates=unix2datetime.(first(df_stops.time,last_stop_time) ./ 1000)
using PlotlyJS
print("\nPlotting!!!")
# Create traces
trace1 = PlotlyJS.scatter(x=times_plot , y=first(data.price,total_sim_time),
                    mode="lines",
                    name="Price")
trace2 = PlotlyJS.scatter(x=sim_times_plot, y=first(df.price,last_simulated_time),
                    mode="lines",
                    name="Simulated Price")


plot([trace1, trace2])



random_only = possible_exps[combo][1]
stop_loss_order= possible_exps[combo][2]
spiked = possible_exps[combo][3]
spike_direction = possible_exps[combo][4]
print("\n\n\n this is the combo: ", combo)

if random_only==1
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - RANDOM ONLY - Seed: " *string(seed_num)))
elseif stop_loss_order==1 && spiked==1 && possible_exps[combo][4]=="DOWN"
    print("\nSPike direction: ", spike_direction)
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - Spiked (DOWN) Stop-loss - Buy Back Strat: " *string(buy_back_strategy) * " - Seed: " *string(seed_num)))
elseif stop_loss_order==1 && spiked==1 
    print("\nSPike direction: ", spike_direction)
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - Spiked (UP) Stop-loss - Buy Back Strat: " *string(buy_back_strategy) * " - Seed: " *string(seed_num)))
elseif stop_loss_order==1 && spiked==0
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - Stop-loss (No Spike) - Seed: " *string(seed_num)))
elseif stop_loss_order==0 && spiked==1 && possible_exps[combo][4]=="DOWN"
    print("\nSPike direction: ", spike_direction)
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - No Stop-loss (Spike (DOWN)) - Seed: " *string(seed_num)))
elseif stop_loss_order==0 && spiked==1 
    print("\nSPike direction shoulw say down: ", spike_direction)
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - No Stop-loss (Spike (UP)) - Seed: " *string(seed_num)))
else
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - No Stops (No Spike) -- Seed: " *string(seed_num)))
end
display(p)
print("\nPlotted")
#savefig(p,"/home/patrick/Desktop/PhD/LOB_Download/Expiriments/Images/seed_"*string(seed_num)*"_spiked_"*string(spiked)*"_SL_"*string(stop_loss_order)*".png" ) 
#print("\nSaved")
sleep(1)
print(last(accounts))
#end
print("\nDoing accounts stuff...")
print("\nBefore updating the spike agent: \n", last(accounts) )
#price = 10000
##################### GET ACCOUNT POSITIONS ######################
for i in range(1, length = length(accounts)-1)
    #Get every agent's starting starting_balances
    starting_balances = starting_shares * price   +    starting_cash
    #Mark to market the value of the shares
    end_value = accounts[i][2]*price+accounts[i][3]
    #Get pnl of agent
    append!(accounts[i], end_value)
    append!(accounts[i], end_value - starting_balances)
end
#Fix the Spike account - becuase it has different starting balances
spike_agent_id= length(accounts)
#Get every agent's starting starting_balances
adjustment_cash = (accounts[spike_agent_id][2]- spike_starting_shares )*price
accounts[spike_agent_id][3] += adjustment_cash
accounts[spike_agent_id][2] += spike_starting_shares-accounts[spike_agent_id][2]
spike_starting_balances = spike_starting_shares * price   +    spike_starting_cash
#Mark to market the value of the shares
spike_end_value = accounts[spike_agent_id][2]*price+accounts[spike_agent_id][3]
#Get pnl of agent
append!(accounts[spike_agent_id], spike_end_value)
append!(accounts[spike_agent_id], spike_end_value - spike_starting_balances)
print("\nAfter updating the spike agent: \n", last(accounts) )




account_df = DataFrame(agent_id=getindex.(accounts,1), type=getindex.(getindex.(accounts, 4), 1) ,end_value=getindex.(accounts, 5), pnl=getindex.(accounts, 6))
gd = groupby(account_df, :type)
accounts_pnls = combine(gd, :pnl => sum)
print("\nThis is the position of the agent types: ", accounts_pnls, "\nAssume the 'market' profited: ", -1*sum(getindex.(accounts, 6)))


accounts_df = DataFrame(type=getindex.(getindex.(accounts, 4), 1), shares = getindex.(getindex.(accounts, 2), 1),cash = getindex.(getindex.(accounts, 3), 1),end_value=getindex.(accounts, 5), pnl=getindex.(accounts, 6))


if save_stuff==1
####### SECTION TO SAVE STUFF #####
MAIN_SAVE_PATH = "/home/patrick/Desktop/PhD/LOB_Download/Newer_Exps_Fix_Problem_Again/"
try; mkdir(MAIN_SAVE_PATH); catch; print("Directory ALready Exists :) "); end
file_name = MAIN_SAVE_PATH * "/seed_"*string(seed_num)*"_spikeDIRECTION_"*string(possible_exps[combo][4])*"_BuyBackStrat_" * string(buy_back_strategy)*"_spiked_"*string(spiked)*"_SL_"*string(stop_loss_order)*"_RandomOnly_"*string(random_only)
#Save the file
jdffile = JDF.save(file_name*"_Accounts.jdf", accounts_df)
jdffile = JDF.save(file_name*"_Data.jdf", df[[:time, :price, :amount_traded, :direction, :agent_type]])
print("\n\nSaved the relevant Data :) \n\n")
end  #End saving stuff

#############################################
# #Load files
# acocunts_df2 = DataFrame(JDF.load(file_name*"_Accounts.jdf"))
# df_2 = DataFrame(JDF.load(file_name*"_Data.jdf"))


print("\nFINISHED - this sim")

end #ENd for loop of combo


end #End loop of num of sims we wanted to try 


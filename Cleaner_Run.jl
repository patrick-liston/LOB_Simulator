#FIX UP SPIKE ONE


#Fix accounts
#https://quantpy.com.au/risk-management/value-at-risk-var-and-conditional-var-cvar/
using CSV
using PyCall
using Random
using DataFrames
using ProgressBars
using BenchmarkTools
using DelimitedFiles
using StatsBase
using PlotlyJS
using Dates
using JDF

SOURCE_PATH = rsplit(Base.source_path(), "/", limit=2)[1]
#Bring in the LOB extrapolation and Order execution functions 
include(SOURCE_PATH * "/LOB_Extrapolation.jl")
include(SOURCE_PATH * "/Buy_Sell_Order_Execution.jl")
include(SOURCE_PATH * "/Everything_Needed_to_Run_Sim.jl")
include(SOURCE_PATH * "/Data_Pre_Post_Process.jl")
include(SOURCE_PATH * "/Agents.jl")

#######################################################################################################################################################################################
#######################################################################################################################################################################################
###       STUFF FOR YOU TO SET  ####

save_stuff = 0 #Save the data?
save_data = 0 #Save the data?
new_sim = 1 #Used to know if we should read in new data
stop_loss_order = 1 #1- If we feature SL's
spiked = 1 #1 - If we want a spike to take place
spike_direction = "UP" #UP or DOWN - depending on desired spike direction
buy_back_strategy = 2 # 1-Never buy back/ assume we get it all back at the end, 2-Buy back in single increment (set by spike_increment), 3-Buy back in 10 increments (set by spike_increment)
random_only=0 #1 - If we want ONLY random agents

total_sim_time=10_000 #Number of trades allowed in the simulation
spike_increment=1_000 #How long to wait after the spike before buying back
#NOTE: spike_time is set to take place in the MIDDLE of the sim. i.e total_time/2

seed_num=rand(1:10000) #random seed
#combos= [[1,1], [1,0], [0,1], [0,0]] #Spike vs No Spike, SL vs No-SL

#Post simulation settings 
plot_it = 1  #Pot - basic
complex_plot_it = 1 #Pot - more complex
save_stuff = 1 # save the data


##### DATA PATHS ####
path="/home/patrick/Desktop/" #Base path 
model_path = "/home/patrick/Desktop/PhD/LOB_Download/Models"
MAIN_SAVE_PATH = SOURCE_PATH * "/test_saves/"

# Simulation data date - (Given we alway use the same month)
date="20" 
limit = total_sim_time * 2 #Data load limit - used to make the data ingestion process quicker

#######################################################################################################################################################################################
#######################################################################################################################################################################################



#Reading in and copying data - NOTE: only gets read in if new_sim set to 1. Will copy data every time though
read_in_lob, read_data, read_in_real_qtys = new_sim == 1 || @isdefined(read_in_real_qtys)==false ? read_in_data(path, date, limit) : read_in_lob, read_data, read_in_real_qtys
lob, data, real_qtys = copy_data(read_in_lob, read_data, read_in_real_qtys)


#Mean and STD used to calculate the size of the orders' stop-loss. (Intention to use the amount to find a Z-score which is then the %added/subtracted to the current price. Resulting in the stop-loss trigger price.)
μ = mean(read_in_real_qtys); σ = std(read_in_real_qtys)



### DOING TIMING STUFF  ###
start_time, end_time, times_to_sim, real_trade_directions, real_prices, 
spike_time, spike_buy_back_time = get_timing(data, total_sim_time, spike_increment)





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

#Spike agent
num_agents=1; spike_starting_shares=1_000_00_000.015 ; spike_starting_cash=5_000_000_000_000.00
try; agent_params=["S", spike_direction, 0] ; catch; agent_params=["S", "UP", 0]; end
accounts=generate_accounts(accounts, num_agents, spike_starting_shares, spike_starting_cash, agent_params)
end #Only allowed other types sometimes
##### Include at least on RL agent? ####

number_of_agents_in_simulation = length(accounts)
print("\nLength of accounts: ", number_of_agents_in_simulation)



########################################################
#######               Set Up STUFF               ######
########################################################

previous_time = 0
trade_prices = [first(data[!,:price])]
price = data.price[findnearest(data.time,start_time)[1]]   #This should be the first trade price from BTCUSDT
previous_price=price
agents = [i for i in range(1, length = length(accounts)-1)]

if typeof(lob)!=DataFrame; print("\nProblem with LOB"); print("\nIt is type: ", typeof(lob)); lob = lob[1]; print("\nNEW is type: ", typeof(lob)) ; end #Ensure we don't get type errors
lob_now, lob = import_orderbook(start_time, lob) #Get first LOB timing 

print("\nStarting simulation\n")
########################################################
#######               MAIN SIMULATION            ######
########################################################
tracking_in = tracking([], [], [], [], [], [], [], [], [], [], [], [], [] )
sl_sells = []
sl_buys = []
df = []
stop_orders_to_execute = []

prices, amounts, lob = update_order_book(lob, first(times_to_sim), price)


if stop_loss_order==1 #Picking which simulator to use - STOP-LOSS ORDER VERSION
total_time=range(1,length=length(times_to_sim))
for n in ProgressBar(total_time)
    current_time=times_to_sim[n]

    previous_time, price,  accounts, tracking_in, lob, prices, amounts, 
            sl_sells, sl_buys, spike_buy_back_time = run_sim_step_sl(previous_time, current_time, price,  
                                real_qtys, accounts, tracking_in, lob, prices, amounts, sl_sells, sl_buys, μ, σ, spike_buy_back_time, n )

end



else #Picking which simulator to use - SIMPLE (NON-SL) VERSION

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
#######           MAKING DATAFRAMES               ######
########################################################
df = DataFrame(time=tracking_in.simmed_times, price = tracking_in.trade_prices , max_price = tracking_in.max_buys,
min_price=tracking_in.max_sells, amount_traded=tracking_in.trade_amounts, trade_value=tracking_in.trade_cashes,
direction=tracking_in.trade_directions, lob_depth=tracking_in.LOB_depth_hit, stop_loss_order=tracking_in.stop_loss_order, agent_type=tracking_in.agent_type)



print("\nMax lob depth hit: ", maximum(tracking_in.LOB_depth_hit))

if plot_it==1 ; simple_plot(data, df, total_sim_time); end

if complex_plot_it==1; complex_plot(data, df, total_sim_time, seed_num, spiked, spike_direction, buy_back_strategy, stop_loss_order, random_only, spike_time, spike_buy_back_time); end


#### ACCOUNT DATA ####
accounts, accounts_df, account_df = final_account_positions(accounts, starting_shares, starting_cash, price, spiked)


#### SAVE DATA ####
if save_stuff==1; save_sim_data(MAIN_SAVE_PATH, accounts_df, df, seed_num, spike_direction, buy_back_strategy, spiked, stop_loss_order, random_only); end

#############################################
# #Load files
# acocunts_df2 = DataFrame(JDF.load(file_name*"_Accounts.jdf"))
# df_2 = DataFrame(JDF.load(file_name*"_Data.jdf"))


print("\nFINISHED - this sim")


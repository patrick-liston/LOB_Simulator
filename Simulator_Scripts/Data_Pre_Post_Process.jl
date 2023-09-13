########################################################
#######   READ IN HISTORICAL DATA FOR SIMULATION   ######
########################################################
function read_in_data(path, date, limit)
    print("\nReading in Data...")
    lob = CSV.read(path*"/BTCUSDT_S_DEPTH/BTCUSDT_S_DEPTH_202111"*date*".csv", DataFrame, limit=limit)
    
    data = CSV.read(path*"/BTCUSDT_TRADES/BTCUSDT-trades-2021-11-"*date*".csv", DataFrame, limit=limit)
    rename!(data,[:trade_Id,:price,:qty,:quoteQty,:time,:isBuyerMaker])
    
    qty = CSV.read(path*"/BTCUSDT_TRADES/Qtys.csv", DataFrame)
    qty = vec(qty[:qty])
    print("\nFinished Reading in Data.")
    return lob, data, qty
end

# lob_new, data_new, qty_new = read_in_data(path, date, limit)

# lob, data, real_qtys = copy_data(lob_new, data_new, qty_new)

# lob_now, lob = import_orderbook(start_time, lob)

########################################################
#######    COPY DATA FOR QUICKER READ-IN TIME     ######
########################################################
function copy_data(read_in_lob, read_in_data, read_in_real_qtys)
    print("\nCopying Data... ")
    real_qtys = copy(first(read_in_real_qtys,total_sim_time*3))
    data = copy(first(read_in_data,total_sim_time*3))
    lob = copy(first(read_in_lob,total_sim_time*3))
    print("\nFinished copying Data.")
    return  lob, data, real_qtys
end

########################################################
#######   DETERMINE TIMINGS (START/END/ASSOCIATED DATA)   ######
########################################################
function get_timing(data, total_sim_time, spike_increment)
    ### DOING TIMING STUFF  ###
    start_time = first(data.time)
    end_time = data.time[total_sim_time]
    times_to_sim = first(data.time,total_sim_time)
    real_trade_directions = first(data.isBuyerMaker,total_sim_time)
    real_prices = first(data.price,total_sim_time)
    spike_time =  times_to_sim[Int(total_sim_time/2)]
    spike_buy_back_time = spike_increment > 0 ? times_to_sim[Int(total_sim_time/2 + spike_increment)] : 0 
    return start_time, end_time, times_to_sim, real_trade_directions, real_prices, spike_time, spike_buy_back_time
end







########################################################
#######       SAVE ACCOUNTS AND TRADE DATA        ######
########################################################
function save_sim_data(MAIN_SAVE_PATH, accounts_df, df, seed_num, spike_direcion, buy_back_strategy, spiked, stop_loss_order, random_only)
try; mkdir(MAIN_SAVE_PATH); catch; print("Directory Already Exists :) "); end
file_name = MAIN_SAVE_PATH * "/seed_"*string(seed_num)*"_spikeDIRECTION_"*string(spike_direcion)*"_BuyBackStrat_" * string(buy_back_strategy)*"_spiked_"*string(spiked)*"_SL_"*string(stop_loss_order)*"_RandomOnly_"*string(random_only)
#Save the file
jdffile = JDF.save(file_name*"_Accounts.jdf", accounts_df)
jdffile = JDF.save(file_name*"_Data.jdf", df[[:time, :price, :amount_traded, :direction, :agent_type]])
print("\n\nSaved the relevant Data :) \n\n")
end


########################################################
#######         PLOT REAL VS SIM - BASIC          ######
########################################################
function simple_plot(data, df, total_sim_time)
    last_time=last(first(data.time,total_sim_time))
    times_plot= unix2datetime.(first(data.time,total_sim_time) ./ 1000)
    last_simulated_time=findnearest(df.time,last_time)[1]
    sim_times_plot=unix2datetime.(first(df.time,last_simulated_time) ./ 1000)


    print("\nPlotting!!!")
    # Create traces
    trace1 = PlotlyJS.scatter(x=times_plot , y=first(data.price,total_sim_time),
                        mode="lines",
                        name="Price")
    trace2 = PlotlyJS.scatter(x=sim_times_plot, y=first(df.price,last_simulated_time),
                        mode="lines",
                        name="Simulated Price")


    p = plot([trace1, trace2], Layout(title = "Simulated vs real price"))
    display(p)
    print("\nPlotted")
    sleep(1)
end

function create_traces(data, df, total_sim_time)
    last_time=last(first(data.time,total_sim_time))
    times_plot= unix2datetime.(first(data.time,total_sim_time) ./ 1000)
    last_simulated_time=findnearest(df.time,last_time)[1]
    sim_times_plot=unix2datetime.(first(df.time,last_simulated_time) ./ 1000)

    # Create traces
    trace1 = PlotlyJS.scatter(x=times_plot , y=first(data.price,total_sim_time),
                        mode="lines",
                        name="Price")
    trace2 = PlotlyJS.scatter(x=sim_times_plot, y=first(df.price,last_simulated_time),
                        mode="lines",
                        name="Simulated Price")
    return trace1, trace2
end




########################################################
#######         PLOT REAL VS SIM - complex          ######
########################################################
function complex_plot(data, df, total_sim_time, seed_num, spiked, spike_direcion, buy_back_strategy, stop_loss_order, random_only, spike_time, spike_buy_back_time)
trace1, trace2 = create_traces(data, df, total_sim_time)

if buy_back_strategy==1
annotation=[
        attr(x=unix2datetime.(spike_time ./ 1000), y=filter(:time => ==(spike_time), df)[:price][1],
            text="Initial spike",
            showarrow=true,
            arrowhead=1)]

else  #Buy back strat has at least one other useful point
    annotation=[
        attr(x=unix2datetime.(spike_time ./ 1000), y=filter(:time => ==(spike_time), df)[:price][1],
            text="Initial spike",
            showarrow=true,
            arrowhead=1),

            attr(x=unix2datetime.(spike_buy_back_time ./ 1000), y=filter(:time => ==(spike_buy_back_time), df)[:price][1],
            text="Buy-back spike",
            showarrow=true,
            arrowhead=1)
    ]
end



if random_only==1
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - RANDOM ONLY - Seed: " *string(seed_num)))
elseif stop_loss_order==1 && spiked==1 && spike_direcion=="DOWN"
    print("\nSpike direction: ", spike_direction)
    p = plot([trace1, trace2], Layout(annotations = annotation, title= "Simulated vs real price  - Spiked (DOWN) Stop-loss - Buy Back Strat: " *string(buy_back_strategy) * " - Seed: " *string(seed_num)))
elseif stop_loss_order==1 && spiked==1 
    print("\nSpike direction: ", spike_direction)
    p = plot([trace1, trace2], Layout(annotations = annotation, title= "Simulated vs real price  - Spiked (UP) Stop-loss - Buy Back Strat: " *string(buy_back_strategy) * " - Seed: " *string(seed_num)))
elseif stop_loss_order==1 && spiked==0
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - Stop-loss (No Spike) - Seed: " *string(seed_num)))
elseif stop_loss_order==0 && spiked==1 && spike_direcion=="DOWN"
    print("\nSpike direction: ", spike_direction)
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - No Stop-loss (Spike (DOWN)) - Seed: " *string(seed_num)))
elseif stop_loss_order==0 && spiked==1 
    print("\nSpike direction shoulw say down: ", spike_direction)
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - No Stop-loss (Spike (UP)) - Seed: " *string(seed_num)))
else
    p = plot([trace1, trace2], Layout(title= "Simulated vs real price  - No Stops (No Spike) -- Seed: " *string(seed_num)))
end
display(p)
print("\nPlotted")
#savefig(p,"/home/patrick/Desktop/PhD/LOB_Download/Expiriments/Images/seed_"*string(seed_num)*"_spiked_"*string(spiked)*"_SL_"*string(stop_loss_order)*".png" ) 
#print("\nSaved")
sleep(1)
end #End the complex plot


########################################################
#######         ANALYSE ACCOUNT POSITIONS         ######
########################################################

function final_account_positions(accounts, starting_shares, starting_cash, price, spiked)
    print("\nDoing accounts stuff...")
    #print("\nBefore updating the spike agent: \n", last(accounts) )
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
    if spiked==1
        #Fix the Spike account - becuase it has different starting balances
        spike_agent_id = length(accounts)
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
    end #Spike agent changes
    #print("\nAfter updating the spike agent: \n", last(accounts) )
    
    account_df = DataFrame(agent_id=getindex.(accounts,1), type=getindex.(getindex.(accounts, 4), 1) ,end_value=getindex.(accounts, 5), pnl=getindex.(accounts, 6))
    gd = groupby(account_df, :type)
    accounts_pnls = combine(gd, :pnl => sum)
    print("\nThis is the position of the agent types: ", accounts_pnls, "\nAssume the 'market' profited: ", -1*sum(getindex.(accounts, 6)), "\n\n")
    return accounts, account_df, account_df
    end

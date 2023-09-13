#= This file contains all the necessary function to extend/extrapolate the order book.
Because the loaded/pre-defined LOB contains only the top 20 LOB levels, an order placed within the simulator may fill n levels.
Thus we require a method to extend the LOB indefinitely. 

We therefore call upon a pre-defined model (found in another folder), which extends the LOB.
This model is an MLP, which was created using a target of the next 500 LOB levels, and the first 20 levels, the slope and volatility of the previous 100 trades as inputs.

This model is called within the main function. Only when the trade being executed exceedes the depth of the currently in use LOB. =#



########################################################
#######   PYTHON: MODELS APPROXIMATE LOB LEVELS   ######
########################################################
py"""
import pickle
import numpy as np
import warnings
warnings.filterwarnings("ignore")
#import scipy
#from sklearn.neural_network import MLPRegressor
def extrapolate_LOB(model_path, lob_amounts, lob_prices, bids):
    amount_filename = f"{model_path}/Bid_Amount_Model.sav" if bids==1 else f"{model_path}/Ask_Amount_Model.sav"    
    price_filename = f"{model_path}/Bid_Amount_Model.sav" if bids==1 else f"{model_path}/Ask_Amount_Model.sav"    
    amount_model = pickle.load(open(amount_filename, 'rb'))
    price_model = pickle.load(open(price_filename, 'rb'))
    #amounts_out = loaded_model.predict(np.array(lob_info).reshape(1,-1))
    return amount_model.predict(np.array(lob_amounts).reshape(1,-1)), price_model.predict(np.array(lob_prices).reshape(1,-1))
"""

########################################################
#######  PREP AMOUNT DATA: WITH VOL AND SLOPE     ######
########################################################
function prep_lob_amount_data(vol::Float64, slope::Float64, data::Vector{Float64})
    lob_info  =  append!(cumsum(data) , vol)
    return  append!(lob_info , slope)
end

########################################################
#######  PREP PRICE DATA: WITH VOL AND SLOPE     ######
########################################################
function prep_lob_price_data(vol::Float64, slope::Float64, data::Vector{Float64}, initial_price::Float64)
    relevant_prices = prep_prices(data, initial_price)
    relevant_prices = append!(relevant_prices , vol)
    return  append!(relevant_prices , slope)
end
  
########################################################
#######   REBASE PRICE DATA TO CORRECT LEVEL      ######
########################################################
function prep_prices(prices::Vector{Float64}, initial_price::Float64)
    return [price-initial_price for  price in prices]
end

########################################################
#######     FINDS SLOPE OF LAST N TRADES          ######
########################################################
function get_slope(data::Vector{Float64})
    slope = 0
    for i in range(2, length = length(data)-1)
        slope += (float(data[i]) - float(data[i-1])) / (float(data[i-1]))
        end
    slope /= length(data) - 1
    return slope
end   

########################################################
#######  FINDS VOLATILITY OF LAST N TRADES        ######
########################################################
function get_volatility(data::Vector{Float64})
volatility=0
for i in range(2,length = length(data)-1)
    volatility += (float(data[i]) - float(data[i-1]))^2
    end
return sqrt(volatility / (length(data)-1))
end

########################################################
####### GET VOLATILITY & SLOPE OF LAST 100 TRADES ######
########################################################
function get_vol_and_slope(tracking_in)
    vol = get_volatility(last(tracking_in.trade_prices, 100))
    slope = get_slope(last(tracking_in.trade_prices, 100))
    return vol, slope
end

########################################################
####### PRICE CORRECTION AMOUNT - CONTINUOUS LEVELS ######
########################################################
function determine_price_correction(prices::Vector{Float64}, price_predictions::Vector{Float64}, initial_price::Float64, bids::Bool)
    allowable_difference = abs(prices[1]-prices[2])
    desired = ifelse(bids==false, initial_price - allowable_difference, initial_price + allowable_difference)
    return desired - price_predictions[1]
end

########################################################
####### MAIN FUNC: GET NEW LOB LEVELS & PRICES    ######
########################################################
function extrapolate_lob(model_path::String, tracking_in, amounts::Vector{Float64}, prices::Vector{Float64}, bids::Bool )
    initial_price = last(prices) #ifelse(bids==false, last(prices), first(prices) )
    vol, slope = get_vol_and_slope(tracking_in)
    lob_amounts = prep_lob_amount_data(vol, slope, amounts)
    lob_prices = prep_lob_price_data(vol, slope, prices, initial_price)


    amount_predictions, price_predictions = py"extrapolate_LOB"(model_path, lob_amounts, lob_prices, bids)
    amount_predictions = broadcast(abs, amount_predictions)
    price_predictions = broadcast(abs, price_predictions)
    amount_predictions = sort(vec(amount_predictions))
    final_amount_predictions = [amount_predictions[i+1]-amount_predictions[i] for i in range(1, length = length(amount_predictions)-1)]
    price_predictions = ifelse(bids==false, sort(vec(price_predictions), rev=true), sort(vec(price_predictions)))

    initial_price = determine_price_correction(prices, price_predictions, initial_price, bids) #Required for BUY side changes

    final_price_predictions = vec([price+initial_price for price in price_predictions])
    return  final_amount_predictions, final_price_predictions
end

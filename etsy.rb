
# This script is going to run every hour. 
# Goals of this script:
# It will call and the Etsy endpoint and will receive receipts. 
# These receipts contain data about the transaction that occured over at Etsy.
# We will recieve this data and process it. 
# Be able to process it in Easypost
# After we obtain ALL the details about the product and the user and where to ship => # Be able to charge the user with Stripe

require 'active_record'
require 'json'
require 'dotenv'
require 'net/http'
require 'uri'
require 'openssl'
require 'stripe'
require 'countries/global'

# Set up mysql database connection
ActiveRecord::Base.establish_connection(
  adapter: 'mysql2',
  host: 'localhost',
  database: '',
  username: 'root',
  password: ''
)

# Define model classes for MySql tables
class EtsyIntegrations < ActiveRecord::Base
end
class EtsyListings < ActiveRecord::Base
end
class EtsyTransactions < ActiveRecord::Base
end
class Products < ActiveRecord::Base
end
class Token < ActiveRecord::Base
end
class Company < ActiveRecord::Base
end
class ShippingFrom < ActiveRecord::Base
end
class Docs < ActiveRecord::Base
end
class Shipping < ActiveRecord::Base
end
class StripeCustomer < ActiveRecord::Base
end
class OrderDatum < ActiveRecord::Base
end
class User < ActiveRecord::Base
end
class Order < ActiveRecord::Base
end
class OrderItem < ActiveRecord::Base
end
class Label < ActiveRecord::Base
end

#load env vars
Dotenv.load('../../config/env.yml')

  #file = File.read('./receiptExample.json')
  #@_json = JSON.parse(file)
  # is_paid = @_json['results'][0]['is_paid']
  # listing_id = @_json['results'][0]['transactions'][0]['listing_id']
  # etsy_user_id = @_json['results'][0]['transactions'][0]['seller_user_id']
  # country_iso = @_json['results'][0]['country_iso']
  # c = ISO3166::Country.new(country_iso)
  # Stripe.api_key = "#{ENV['STRIPE_KEY']}"
  # endpoint_secret = 'whsec_zDGSgTjX2PlJqhESgQg0DyMugxLb8sGw'
  # @country = c.common_name
  # @etsy_items = []
  # @cart_products = []
  # @template = []
  # @sku_array = []
  # @shipping_us = 0
  # @shipping_intl = 0
  # @order_price = 0
  # @total_shipping = 0
  # @total = 0 
  # @est_tax = 0
  # @order_total = 0
  # @partner_order_id = rand(36**5).to_s(36)
  # @stripe_id = nil
  # @op_order_id = ""
  # @payment_intent_id = ""
  # @user_id_pvp = ""
  # @address_id = ""
  Stripe.api_key = "#{ENV['STRIPE_KEY']}"
  endpoint_secret = ''

  

  # @address_obj = {
  #   # EasyPost params
  #   fname: @_json['results'][0]['name'],
  #   city: @_json['results'][0]['city'],
  #   state: @_json['results'][0]['state'],
  #   zip: @_json['results'][0]['zip'],
  #   street_address: @_json['results'][0]['first_line']
  # }

  # #ship_to Params
  # @fname = @address_obj[:fname]
  # @street_address = @address_obj[:street_address]
  # @city = @address_obj[:city]
  # @zip = @address_obj[:zip]
  # @state = @address_obj[:state]
  # @is_paid = @_json['results'][0]['is_paid']
  # @quantity = @_json['results'][0]['transactions'][0]['quantity']



  #get from etsy_integrations table (retrieve listing_ids array)
  #push Listing_ids in a temp_array
  #then call get_shop_receipts (query by if it's paid already) and compare the listing_ids that get retrieved
  #if it matches any in our listing_ids array then query etsy_transacations and check by etsy_transacation_id from receipt
  #if etsy_transaction_id matches that listing_Id, do NOT execute script. and proceed with the next listing_id check.
  #if etsy_transaction_id does NOT match, execute the script and charge the customer 
  #then post transaction_id, company name and listing_id to db.


  #maybe do 1 company traverse though listing_ids water fall.

  def get_shop_receipts(etsy_user_id, access_token)
    begin
      @integration = EtsyListings.find_by(etsy_user_id: etsy_user_id) 
      _access_token = access_token
      client_id = ENV.fetch('ETSY_API_KEY')
      @shop_id = @integration.shop_id

      url=URI( "#{ENV['ETSY_URL']}" + "/application/shops/#{@shop_id}/receipts")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request = Net::HTTP::Get.new(url)
      request["content-type"] = 'application/x-www-form-urlencoded'
      request["Authorization"] = "Bearer #{_access_token}"
      request["x-api-key"] = "#{client_id}"
      puts 'req: getShopReceipts'
      response = http.request(request)
      _response = JSON.parse(response.read_body)
      #puts response.read_body

      return _response


    rescue StandardError => e
      puts "error in get shop receipts::: #{e}"
    end
  end
  def refresh_token(etsy_user_id)
    begin
      @integration = EtsyIntegrations.find_by(etsy_user_id: etsy_user_id) 
      client_id = ENV['ETSY_API_KEY']
      token_refresh = @integration.token_refresh
      url = URI("#{ENV['ETSY_URL']}" + "/public/oauth/token")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request = Net::HTTP::Post.new(url)
      request["content-type"] = 'application/x-www-form-urlencoded'
      request.body = "grant_type=refresh_token&client_id=#{client_id}&refresh_token=#{token_refresh}"
      response = http.request(request)
      _response = JSON.parse(response.read_body)
      puts response.read_body
      if @integration.persisted?
        @integration = EtsyIntegrations.where(etsy_user_id: etsy_user_id).update(access_token: _response['access_token'])
        @integration = EtsyIntegrations.where(etsy_user_id: etsy_user_id).update(token_refresh: _response['refresh_token'])
      else  
        puts 'did not update db'
      end
     end
  end

  def grab_items_from_order(response)
    @etsy_items = []
    transactions = response['results'][0]['transactions']
    
    transactions.each_with_index {|i, index|
    item = {
      listing_id: i['listing_id'],
      quantity: i['quantity'],
      transaction_id: i['transaction_id'],
      shop_id: @shop_id
    }
    @etsy_items.append(item)
    }
  end

  def welcome(etsy_user_id)
    begin
      @integration = EtsyIntegrations.find_by(etsy_user_id: etsy_user_id) 
      access_token = @integration.access_token
      @user_id = @integration.user_id
      @company_id = @integration.company_id
      client_id = ENV[('ETSY_API_KEY')]
      request_header = {'Content-type': "application/json",'x-api-key': "#{client_id}", 'Authorization': "Bearer #{access_token}", "Accept:": "application/json"}
      url=URI( "#{ENV['ETSY_URL']}" + "/application/users/" + "#{etsy_user_id}")
      http = Net::HTTP::new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Get.new(url, request_header)
      res = http.request(req)
      puts 'response:'
      puts JSON.parse(res.body)
      result = JSON.parse(res.body)
      return access_token

    end
  end

  # def refresh_token(etsy_user_id)
  #   begin
  #     @integration = EtsyIntegrations.find_by(etsy_user_id: etsy_user_id) 
  #     client_id = ENV['ETSY_API_KEY']
  #     token_refresh = @integration.token_refresh
  #     url = URI("#{ENV['ETSY_URL']}" + "/public/oauth/token")
  #     http = Net::HTTP.new(url.host, url.port)
  #     http.use_ssl = true
  #     http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  #     request = Net::HTTP::Post.new(url)
  #     request["content-type"] = 'application/x-www-form-urlencoded'
  #     request.body = "grant_type=refresh_token&client_id=#{client_id}&refresh_token=#{token_refresh}"
  #     response = http.request(request)
  #     _response = JSON.parse(response.read_body)
  #     puts response.read_body
  #     if @integration.persisted?
  #       @integration = EtsyIntegrations.where(etsy_user_id: etsy_user_id).update(access_token: _response['access_token'])
  #       @integration = EtsyIntegrations.where(etsy_user_id: etsy_user_id).update(token_refresh: _response['refresh_token'])
  #     else  
  #       puts 'did not update db'
  #     end
  #    end
  # end


  def find_template
    @etsy_items.each {|i|  
    @listing = EtsyListings.find_by(listing_id: i[:listing_id])
    template = {
      sku: @listing.sku,
      image_url: @listing.artwork_url,
      company_id: @listing.company_id,
      user_id: @listing.user_id,
      username: @listing.username,
      blank_img_url: @listing.blank_img_url,
      quantity: i[:quantity]
      #po: rand(36**5).to_s(36)
      }
    @template.append(template)
    }
  end

  def send_to_shippings_table
    if Shipping.where(po: @partner_order_id).exists?
      puts "Success"
    else
      shipping = Shipping.new(name: @fname, street_address: @street_address, state: @state, city: @city, zip_code: @zip, country: @country,
      po: @partner_order_id, user_id: @user_id_pvp)
      if shipping.save
        puts "shipping saved successfully to db"
        @address_id = shipping
      end
    end
  end

  def product_list_by_sku(sku)
    @product = Products.find_by(sku: sku)
    return @product
  end

  def get_token(user_id)
    @token = Token.find_by(user_id: user_id)
    return @token.token
  end

  def get_company(user_id)
    @company = Company.find_by(user_id: user_id)
    return @company.company_name
  end

  def get_pvp_user
    user = User.find_by(user_id: @user_id)
    if user
      # render json: {result:'success', data: user }
      @user_id_pvp = user.id
      return @user_id_pvp
    else 
      # render json: {result: "user not found"}
      puts "user not found"
    end
  end

  def save_order_items(order_items)
    _order_items = order_items
    _order_items.each do |item|
    item_to_add = OrderItem.new(order_id: item[:order_id], sku: item[:sku], quantity: item[:quantity], tax: item[:tax], us_shipping: item[:shipping_us], intl_shipping: item[:shipping_intl], addl_shipping: item[:shipping_addl], total_shipping: item[:total_shipping], company_id: item[:company_id], price: item[:price])
      if item_to_add.save
        puts 'successfully added item to db'
      else
        puts 'order item did NOT save'
      end
    end
  end

  def save_op_order(final_pvp_order)
    puts "finalpvpORDER IN DEF::::::: #{final_pvp_order}"
    order = Order.new(op_order_id: final_pvp_order[:op_order_id], company_id: final_pvp_order[:company_id], user_id: final_pvp_order[:user_id], op_id: final_pvp_order[:op_id], 
      username: final_pvp_order[:username], po: final_pvp_order[:po], order_time: final_pvp_order[:order_time], ship_to_company: final_pvp_order[:ship_to_company], 
      fname: final_pvp_order[:fname], lname: final_pvp_order[:lname], address1: final_pvp_order[:address1], address2: final_pvp_order[:address2], city: final_pvp_order[:city],
      state: final_pvp_order[:state], zip: final_pvp_order[:zip], country: final_pvp_order[:country], country_name: final_pvp_order[:country_name], total_price: final_pvp_order[:total_price],
      pay_type: final_pvp_order[:pay_type], pay_status: final_pvp_order[:pay_status], address_id: final_pvp_order[:address_id], total_tax: final_pvp_order[:total_tax], 
      items_price: final_pvp_order[:items_price], total_shipping: final_pvp_order[:total_shipping], total_qty: final_pvp_order[:total_qty], charge_id: final_pvp_order[:charge_id], source: final_pvp_order[:source])
    if order.save
      #render json: {result: "success!", order: order}
      puts "success: #{order}"
    end
  end


  def save_order_data(_order_data)
    data = _order_data
    puts "data #{data}"
    
  #  order_data = OrderDatum.new(data)

    order_data = OrderDatum.new(order_data: data[:order_data], company_id: data[:company_id], po: data[:po])
    if order_data.save
      #render json: {result: "success!", order: order_data}
      puts "Success!: #{order_data}"
    end
  end

  def get_order(op_order_id)
    id = op_order_id
    @final_order = Order.where(op_order_id: id)
    if @final_order
      puts "FINAL ORDER::: #{@final_order}"
    return @final_order
    end
  end

  def delete 
    data = JSON.parse(request.body.read)
    id=data.to_i
    @orders = Order.find(id).destroy
    if @orders
      render json:{message: "Success!"}
    end
  end

  # def send_order_email(data)
  #   order = data
  #   puts order
  #   UserMailer.with(order: order).new_order_email(order).deliver_now
  # end

  def create_label(label_data)
    label = Label.new(op_order_id: label_data[:op_order_id], po: label_data[:po], company_id: label_data[:company_id])
    if label.save
        puts "saved to labels table"
    end
  end


  #fix this
  def get_shipping_from_info(company_id)

    address = ShippingFrom.find_by(id:1)
    puts 'shipping FROMMMMM:::::'
    puts address.address1

    return address
  end

  def get_resell_cert(company_id)
    @doc = Docs.find_by(company_id: company_id)
    return @doc
  end

  def get_facility(data_obj)
    begin
      data = data_obj
      _data = data.to_json
      request_header = {'Content-type': 'application/json'}
      url = URI("#{ENV['PORTAL_URL']}" + "/get_coast_from")
      http = Net::HTTP::new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Post.new(url, request_header)
      req.body = _data
      res = http.request(req)  
      result = res.body 
      if result
        if(result.include? '<') #to know if response is xml format. mayber there's a better way.
          
        else 
          final_result =  eval(result)
          return final_result
        end
      end
    end
  end

  def get_tariff(skus)
    begin
      data = skus
      _data = data.to_json
      request_header = {'Content-type': 'application/json'}
      url = URI("#{ENV['PORTAL_URL']}" + "/get_product_tariff_number")
      http = Net::HTTP::new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Post.new(url, request_header)
      req.body = _data
      res = http.request(req)  
      result = res.body 
      if result
        if(result.include? '<') #to know if response is xml format. mayber there's a better way.
          render json: {data:{result:result}}
        else 
          final_result =  eval(result)
          return final_result
        end
      end
    end
  end


  #fix the finalObj. this current only will work for single orders. i think i fixed this. i call this in a loop.
  def create_easypost_item(itemObj)

    sku = itemObj[:product].sku
    quantity = itemObj[:quantity]
    price = itemObj[:product].price.gsub(/[^0-9\.]/, '')
    description = itemObj[:product].material + " " + itemObj[:product].variant_name
    image_url = itemObj[:image_url]

    puts "image_url :#{image_url}"
    tariffNum = get_tariff({sku: sku})

    finalObj = {
      sku: sku,
      quantity: quantity,
      price: price,
      tariffNum: tariffNum['tariffNum'],
      description: description,
      image_url: image_url
    }

    return finalObj
  end


  def createEasypost_order(easypostObj)
    begin
      data = easypostObj
      _data = data.to_json
      request_header = {'Content-type': 'application/json'}
      url = URI("#{ENV['EASYPOST_URL']}" + "/rates/ship")
      http = Net::HTTP::new(url.host, url.port)
      #http.use_ssl = true
      #http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Post.new(url, request_header)
      req.body = _data
      res = http.request(req)  
      puts res
      result = res.body 
      if result
        if(result.include? '<') #to know if response is xml format. mayber there's a better way.
          render json: {data:{result:result}}
        else 
          return JSON.parse(result)
        end
      end
    end
  end

  def charge(data)
    # payload =>
    # data = {
    # "id": 1998,
    # "total": "9.82",
    # "stripe_id": "cus_NCstMxW2tmJylF",
    # "pay_type": "default_card",
    # "description": "Company: luistest2, sku: 21108(1) "
    # }


    i_key = SecureRandom.hex
    puts 'Inside Charge method. Idempotency key:'
    puts i_key
    total = (data[:total].to_f) * 100

    _total = total.to_i
    
    begin
    @payment_id = Stripe::PaymentMethod.list({
      customer: data[:stripe_id],
      type: 'card'
    
    })
    rescue => e
       #render json: {message: 'failed', result: @payment_id}
      puts "There has been an error: #{e} : #{@payment_id}"
    end


    intent = Stripe::PaymentIntent.create(
        {amount: _total,
        currency: 'USD',
        customer: data[:stripe_id],
        payment_method: @payment_id['data'][0]['id'],
        confirm: true,
        off_session: false,
        description: data[:description],
        },{
          idempotencyKey: i_key
        }
      )

      if intent
        #render json: {message: "success", result: intent}
        puts "success: #{intent}"
        @payment_intent_id = intent['charges']['data'][0]['payment_intent']
        @charge_id = intent['charges']['data'][0]['id']
      end
    rescue Stripe::CardError => e
      # Error code will be authentication_required if authentication is needed
      puts "Error is: #{e.error.code}"
      payment_intent_id = e.error.payment_intent.id
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      puts payment_intent.id
      _data = { clientSecret: payment_intent['client_secret'],
        id: payment_intent['id']}
    
      # Send publishable key and PaymentIntent details to client
      #render json: { result: _data, message: "Success!"
      puts "Success!: #{_data}"

  end 

  def send_op(op_order)
    begin 
     data = op_order
     _data = data.to_json
     request_header = {'Content-type': 'application/json'}
     url=URI("#{ENV['API_URL']}" + "/send_order")
     http = Net::HTTP::new(url.host, url.port)
     http.use_ssl = true
     http.verify_mode = OpenSSL::SSL::VERIFY_NONE
     req = Net::HTTP::Post.new(url, request_header)
     req.body=_data
     res = http.request(req)  
     result = res.body 
     if result
      if(result.include? '<') #to know if response is xml format. mayber there's a better way.
       # render json: {data:{result:result}}
        puts result
      else
        json_data = JSON.parse(result)
        @op_order_id = json_data['result']['reference_id']
        puts "Success: #{json_data}"
      end
     end
    end
  end




  def handleQuantity
    item_order_price = 0
    item_order_shipping = 0
    single_item_shipping = nil
    total_cart_quantity = 0
    my_ca_tax = 0
    country = @country_iso
    @pre_sorted_cart_products = []
    
    @cart_products.each {|i|
      total_cart_quantity += i[:quantity]
      priceNoSymbol = (i[:product].price.gsub(/[^0-9\.]/, '')).to_f
      puts "priceNoSymbol: #{priceNoSymbol}"
      item_order_price +=  priceNoSymbol * i[:quantity]
      puts "item_order_price: #{item_order_price}"
      tempTax = ((priceNoSymbol * 0.11) * i[:quantity]).to_f
      puts "tempTax: #{tempTax}"
      my_ca_tax += tempTax
    }
    my_ca_tax = '%.2f' % my_ca_tax.to_f
    puts "myCaTax: #{my_ca_tax}"
    

    @pre_sorted_cart_products = JSON.parse(@cart_products.to_json)
 
    if single_item_shipping == nil && country == 'United States' || country == nil  || country == 'US' || country == 'EE. UU.' || country == ''
      puts 'Domestic ship'

      sorted_cart_products = @pre_sorted_cart_products.sort {|a, b|
        b_shipping = b['product']['shipping_us'].gsub(/[^0-9\.]/, '').to_f
        a_shipping = a['product']['shipping_us'].gsub(/[^0-9\.]/, '').to_f
        b_shipping - a_shipping
        }
      
      single_item_shipping = sorted_cart_products[0]['product']['shipping_us'].gsub(/[^0-9\.]/, '').to_f
      @shipping_us = single_item_shipping
      
      puts "Shipping_us: #{@shipping_us}"

    elsif single_item_shipping == nil && country != 'United States' || country != nil || country != 'US' || country != 'EE. UU.' || country != 'Puerto Rico' || country != ''
      puts 'international ship'
      sorted_cart_products = @pre_sorted_cart_products.sort {|a, b|
      b_shipping = b['product']['shipping_intl'].gsub(/[^0-9\.]/, '').to_f
      a_shipping = a['product']['shipping_intl'].gsub(/[^0-9\.]/, '').to_f
      b_shipping - a_shipping
      }
          
      single_item_shipping = sorted_cart_products[0]['product']['shipping_us'].gsub(/[^0-9\.]/, '').to_f
      @shipping_intl = single_item_shipping
    end


     # Not doing Expedited shipping, so just apply this formula:
    (item_order_shipping +=  single_item_shipping.to_f + (total_cart_quantity - 1) * 4.99).to_f
    @order_price = (item_order_price).to_f
    @total_shipping = total_cart_quantity == 1 ? (item_order_shipping).to_f : @easypost_rate ? @easypost_rate : (item_order_shipping).to_f
     
    totalOrderPrice = item_order_price + @total_shipping.to_f
    @total = ('%.2f' % totalOrderPrice).to_f
     
    @total_cart_quantity = total_cart_quantity

    if @state != 'CA'
      @est_tax = 0
      puts '1:: '
    else
      if @resale_cert
        puts '2:: '
        @est_tax = 0
      else 
        puts '3:: '
        @est_tax = my_ca_tax.to_f
      end
    end

    @order_total = '%.2f' % (@total + @est_tax).to_f

    puts "order_price: #{@order_price}"
    puts "total_shipping: #{@total_shipping}"
    puts "est_tax: #{@est_tax}"
    puts "total? subtotal?: #{@total}"
    puts "order_total #{@order_total}"
  end


  def generate_order(item_info, ship_to_info, token, companyName, ship_from_info, partner_order_id, shipping_option, shipMethod, shipCode, easypostId)

    today = Time.new
    date = today.strftime("%Y-%m-%d")
    time = today.strftime("%H:%M:%S")
    date_time = date + ' ' + time
    total_item_quantity = 0

    order_item = []

    item_info.each {|i|
      total_item_quantity += i[:quantity]
        item = {
          order_item_product_code: i[:sku],
          order_item_partner_product_code: i[:po] || i[:sku],
          order_item_quantity: i[:quantity],
          order_item_image_url: i[:image_url],
          order_item_image_ftp: ""
        }
      op_order = {
        order: {
          order_items: {
            order_item: "#{order_item.append(item)}"
          }
        }
      }
    }

  puts "Total Item Quantity: #{total_item_quantity}"


   #some of these are commented because it might be different when I recieve data from an actual endpoint response
    op_order = {
      order: {
        order_info: {
          partner_order_id: partner_order_id,
          username: companyName,
          token: token,
          order_datetime: date_time,
          source: "pvp.com",
          callback_url: "https://services.printversepro.com/order_info/#{partner_order_id}",
          easypost_order_id: easypostId ? easypostId : ""
        },
        ship_from_info: {
          # ship_from_company: ship_from_info['company_name'],
          # ship_from_fname: ship_from_info['first_name'],
          # ship_from_lname: ship_from_info['last_name'],
          # ship_from_street1: ship_from_info['address1'],
          # ship_from_street2: ship_from_info['address2'],
          # ship_from_street3: ship_from_info['address3'],
          # ship_from_city: ship_from_info['city'],
          # ship_from_stateprov: ship_from_info['state'] || "N/A",
          # ship_from_country: ship_from_info['country'],
          # ship_from_country_name: ship_from_info['country_name'],
          # ship_from_zip: ship_from_info['zip'],
          ship_from_company: ship_from_info[:company_name],
          ship_from_fname: ship_from_info[:first_name],
          ship_from_lname: ship_from_info[:last_name],
          ship_from_street1: ship_from_info[:address1],
          ship_from_street2: ship_from_info[:address2],
          ship_from_street3: ship_from_info[:address3],
          ship_from_city: ship_from_info[:city],
          ship_from_stateprov: ship_from_info[:state] || "N/A",
          ship_from_country: ship_from_info[:country],
          ship_from_country_name: ship_from_info[:country_name],
          ship_from_zip: ship_from_info[:zip],
          ship_from_phone: "0000000000",
          ship_from_email: "info@photomugs.com"
        },
       ship_to_info: {
          # ship_to_company: ship_to_info['company'],
          # ship_to_fname: ship_to_info['fname'],
          # ship_to_lname: ship_to_info['lname'],
          # ship_to_street1: ship_to_info['street1'],
          # ship_to_street2: ship_to_info['steet2'],
          # ship_to_street3: ship_to_info['street3'],
          # ship_to_city: ship_to_info['city'],
          # ship_to_stateprov: ship_to_info['state'] ? ship_to_info['state'] : 'X',
          # ship_to_country: ship_to_info['country_code'],
          # ship_to_country_name: ship_to_info['country'],
          # ship_to_zip: ship_to_info['zip'],
          # ship_to_email: ship_to_info['email'],
          # ship_to_method: 'STANDARD',
          # ship_to_code: 'STANDARD',
          ship_to_company: ship_to_info[:company],
          ship_to_fname: ship_to_info[:fname],
          ship_to_lname: ship_to_info[:lname],
          ship_to_street1: ship_to_info[:street1],
          ship_to_street2: ship_to_info[:street2],
          ship_to_street3: ship_to_info[:street3],
          ship_to_city: ship_to_info[:city],
          ship_to_stateprov: ship_to_info[:state] ? ship_to_info[:state] : 'X',
          ship_to_country: ship_to_info[:country_code],
          ship_to_country_name: ship_to_info[:country],
          ship_to_zip: ship_to_info[:zip],
          ship_to_email: ship_to_info[:email],
          ship_to_method: (easypostId && total_item_quantity > 1) ? shipMethod : (shipping_option == 'Expedited' ? "DhlEcs" : 'STANDARD'),
          ship_to_code: (easypostId && total_item_quantity > 1) ? shipCode : (shipping_option == 'Expedited' ? (ship_info['country_code'] == 'US' ? "DHLParcelExpedited" : "DHLParcelInternationalStandard") : 'STANDARD')
        },
        order_items: {
          order_item: order_item
        },
        order_attachments: {
          order_packlist: 'DEFAULT',
          order_packlist_ftp: ''
        }
      }
    }

   @op_order =  op_order
    return @op_order

  end


  def easypostFn
    @items = []

    #grab_items_from_order
    find_template
    @template

    @template.each {|i|

     sku = i[:sku]

     temp = {
      product: product_list_by_sku(sku),
      quantity: i[:quantity],
      image_url: i[:image_url]
     }
      @cart_products.append(temp)
      @sku_array.append(sku)
    }
    

    cartCopy = @cart_products

    cartCopy.each {|i|
    tempItem = create_easypost_item(i)
    @items.append(tempItem)
    }


    facilityObj = {
      zipcode: @address_obj[:zip],
      skus: @sku_array,
      country: @country
    }

   facility = get_facility(facilityObj)

   
   
   address_obj = {
    name: @address_obj[:fname],
    street1: @address_obj[:street_address],
    street2: @address_obj[:street_address2],
    city: @address_obj[:city],
    state: @address_obj[:state],
    zip: @address_obj[:zip],
    country: @country,
    phone: "",
    shipping_option: "Standard"
   }


   puts @address_obj


    easypostObj = {
      intl: false,
      facility: facility['facility'],
      address: address_obj,
      items: @items
      }


    easypostData = createEasypost_order(easypostObj)
    @easypost_id = easypostData['id']
    @shipping_rate = easypostData['shippingRate']
    shipMethod = easypostData['shippingCarrier']
    shipCode = easypostData['shippingMethod']
    @easypost_rate = ('%.2f' % (@shipping_rate + (@shipping_rate * 0.6))).to_f
    token = get_token(@user_id)
    companyName = get_company(@user_id)
    order_item = []

    puts "EasyPost Rate: #{@easypost_rate}"


    #fix this so its not static
    ship_to_info = {
      company: '',
      fname: @fname,
      lname: @lname,
      street1: @street_address,
      street2: @street_address2,
      street3: '',
      city: @city,
      state: @state,
      zip: @zip,
      email: @buyer_email,
      country_name: @country,
      country_code: @country_iso,
      country: @country
    }

    # @street_address = @address_obj[:street_address]
    # @street_address2 = @address_obj[:street_address2]
    # @city = @address_obj[:city]
    # @zip = @address_obj[:zip]
    # @state = @address_obj[:state]
    # @fname, @lname = response['results'][0]['name'].split(' ')
    # @quantity = response['results'][0]['transactions'][0]['quantity']

    
   ship_from = get_shipping_from_info(@company_id)

   ship_from_info = {
    company_name: ship_from.company_name,
    first_name: ship_from.first_name,
    last_name: ship_from.last_name,
    address1: ship_from.address1,
    address2: ship_from.address2,
    city: ship_from.city,
    state: ship_from.state,
    country: ship_from.country,
    zip: ship_from.zip

   }



    puts 'populated AFTER::::::::::'
    puts "easypost_id: #{@easypost_id}"
    puts "Shipping_rate: #{@shipping_rate}"
    puts "easypostRate: #{@easypost_rate}"
    
    send_to_shippings_table
    handleQuantity




   opOrder = generate_order(@items, ship_to_info, token, companyName, ship_from_info, @partner_order_id, address_obj['shipping_option'], shipMethod, shipCode, @easypost_id)


  end


  def get_stripe_id
    _id = @user_id
    @stripe = StripeCustomer.where("user_id = ?", _id).select("id", "stripe_id, bill_method", "is_default", "last4", "exp_date")
    if @stripe
      puts @stripe.to_json
      puts @stripe[0].stripe_id
    else 
      # render json: {result: 'error', data: "Error"}
    end
  end
  
  def update_stripe_order_id(stripeData)
    data = stripeData
    puts 'insde update stripe order id:::::::::::'
    puts data
    puts data[:intent_id]
    stripe = Stripe::PaymentIntent.update(
      data[:intent_id],
      {metadata: {op_order_id: data[:order_id]}, description: data[:description]},
    )
    if(stripe)
      puts "Updated StripeMetaData."
    end
  
  end

  def updateStripeMetaData(order_id, stripe_intent_id, items)

    puts "metadata FN: #{order_id}"
    items.append(", ; op_order_id: #{order_id}")

    stripeData = {
      order_id: order_id,
      intent_id: stripe_intent_id,
      description: items.join("")
    }

    puts "stripeData: #{stripeData}"

    update_stripe_order_id(stripeData)

  end

  def save_order_data_fn
    order_data = {
      order_data: @op_order.to_json,
      company_id: @company_id,
      po: @partner_order_id
    }

    #posts it order_data table. it works
    save_order_data(order_data)

  end


    def process_payment
      items = []
      @companyName = get_company(@user_id)


      items.append("Company: #{@companyName}")

    @cart_products.each {|i|
      items.append(", sku: #{i[:product].sku} (#{i[:quantity]})")
     }      
      data = {
        total: @order_total,
        stripe_id: @stripe[0].stripe_id,
        pay_type: 'default_card',
        description: items.join(""),
      }
      puts "join: #{items.join("")}"

      puts "the items: #{items}"
      puts "data sending: #{data}"

      charge(data)
      send_to_databases(items, @payment_intent_id, @charge_id)

    end

    

    def send_to_databases(items, payment_intent_id, charge_id)
      save_order_data_fn

      #sends OP
      send_op(@op_order)

      updateStripeMetaData(@op_order_id, payment_intent_id, items)


      final_pvp_order = generate_pvp_order(@op_order, charge_id)

      save_op_order(final_pvp_order)
      send_order_items

      get_final_order
      
    end

    def generate_pvp_order(op_order, charge_id)


      address_id_obj = {
        id: @address_id.id,
        name: @address_id.name,
        street_address: @address_id.street_address,
        city: @address_id.city,
        state: @address_id.state,
        zip_code: @address_id.zip_code,
        country: @address_id.country,
        created_at: @address_id.created_at,
        updated_at: @address_id.updated_at,
        user_id: @address_id.user_id,
        street_address_2: @address_id.street_address_2,
        po: @address_id.po
      }

      puts "address.id #{@address_id.id}"

      pvp_order = {
        op_order_id: @op_order_id,
        company_id: @company_id,
        user_id: @user_id_pvp,
        op_id: @user_id,
        po: op_order[:order][:order_info][:partner_order_id],
        order_time: op_order[:order][:order_info][:order_datetime],
        ship_to_company: op_order[:order][:ship_to_info][:ship_to_company],
        fname: op_order[:order][:ship_to_info][:ship_to_fname],
        lname: op_order[:order][:ship_to_info][:ship_to_lname],
        address1: op_order[:order][:ship_to_info][:ship_to_street1],
        address2: op_order[:order][:ship_to_info][:ship_to_street2],
        city: op_order[:order][:ship_to_info][:ship_to_city],
        state: op_order[:order][:ship_to_info][:ship_to_stateprov],
        zip: op_order[:order][:ship_to_info][:ship_to_zip],
        country: op_order[:order][:ship_to_info][:ship_to_country],
        country_name: op_order[:order][:ship_to_info][:ship_to_country_name],
        total_price: @order_total,
        pay_type: "default_card",
        address_id: address_id_obj,
        items_price: @order_price,
        total_tax: @est_tax,
        total_shipping: @total_shipping,
        total_qty: @total_cart_quantity,
        username: op_order[:order][:order_info][:username],
        charge_id: charge_id,
        pay_status: "Paid" 
      }
      puts "::::pvpORDER:: #{pvp_order}"
      
      final_pvp_order = pvp_order

      return final_pvp_order
    end

    def send_order_items

      order_items = []

      pre_sorted_cart_products = JSON.parse(@cart_products.to_json)

      if @country == 'United States' || @country == 'US' || @country == 'EE. UU.'
        sorted_cart_products = pre_sorted_cart_products.sort {|a, b|
        b_shipping = b['product']['shipping_us'].gsub(/[^0-9\.]/, '').to_f
        a_shipping = a['product']['shipping_us'].gsub(/[^0-9\.]/, '').to_f
        b_shipping - a_shipping
        }
      else 
        sorted_cart_products = pre_sorted_cart_products.sort {|a, b|
        b_shipping = b['product']['shipping_intl'].gsub(/[^0-9\.]/, '').to_f
        a_shipping = a['product']['shipping_intl'].gsub(/[^0-9\.]/, '').to_f
        b_shipping - a_shipping
        }

      end


      puts "SORTEDCARTPRDUCTS::::: #{sorted_cart_products}"

      sorted_cart_products.each {|i|

      if @country == 'United States' || @country == 'US' || @country == 'EE. UU.'
        shipping_us = i['product']['shipping_us'].gsub(/[^0-9\.]/, '').to_f
      else 
        shipping_intl = i['product']['shipping_intl'].gsub(/[^0-9\.]/, '').to_f
      end

      order_items_data = {
        order_id: @op_order_id,
        sku: i['product']['sku'],
        quantity: i['quantity'],
        tax: @est_tax,
        shipping_us: shipping_us,
        shipping_intl: shipping_intl,
        total_shipping: @total_shipping,
        company_id: @company_id,
        price: (i['product']['price'].gsub(/[^0-9\.]/, '')).to_f
      }
      
      order_items.append(order_items_data)
      }

      puts "saveOrderItems::::: #{order_items}"

      save_order_items(order_items)


    end

    def post_to_transactions

      puts "items in trans: #{@etsy_items}"
      @etsy_items.each {|item|
      @transaction = EtsyTransactions.new(transaction_id: item[:transaction_id], company_name:@companyName , listing_id: item[:listing_id] , shop_id:item[:shop_id])
      }
      if @transaction.save
        puts "transaction saved successfully to db"
      end

      @etsy_items = []
    end

    def get_final_order
      curr_order = get_order(@op_order_id)

      puts "getFINALORDE "
      puts curr_order[0]

      #send_order_email(curr_order)

      label_data = {
        po: curr_order[0].po,
        op_order_id: curr_order[0].op_order_id,
        company_id: curr_order[0].company_id
      }
      create_label(label_data)
      post_to_transactions


    end

    def send_to_shippings_table
      if Shipping.where(po: @partner_order_id).exists?
        puts "Success"
      else
        shipping = Shipping.new(name: @fname, street_address: @street_address, state: @state, city: @city, zip_code: @zip, country: @country,
        po: @partner_order_id, user_id: @user_id_pvp)
        if shipping.save
          puts "shipping saved successfully to db"
          @address_id = shipping
        end
      end
    end






  def driver(etsy_user_id)
    refresh_token(etsy_user_id)
    #access_token = welcome(etsy_user_id)
   #get_shop_receipts(etsy_user_id, access_token)
    # get_pvp_user
    # easypostFn
    # get_stripe_id
    # process_payment
  end  
  
#driver(756883914)


  def populate_globals(response)

    # is_paid = response['results'][0]['is_paid']
    # listing_id = response['results'][0]['transactions'][0]['listing_id']
    # etsy_user_id = response['results'][0]['transactions'][0]['seller_user_id']
    # country_iso = response['results'][0]['country_iso']
    # c = ISO3166::Country.new(country_iso)
    # access_token = welcome(etsy_user_id)
    # @country_iso = country_iso
    # @buyer_email = response['results'][0]['buyer_email']

    puts "res:: #{response}"

    is_paid = response['is_paid']
    #listing_id = response['results'][0]['transactions'][0]['listing_id']
    etsy_user_id = response['seller_user_id']
    country_iso = response['country_iso']
    c = ISO3166::Country.new(country_iso)
    access_token = welcome(etsy_user_id)
    @country_iso = country_iso
    @buyer_email = response['buyer_email']

    @country = c.common_name
   # @etsy_items = []
    @cart_products = []
    @template = []
    @sku_array = []
    @shipping_us = 0
    @shipping_intl = 0
    @order_price = 0
    @total_shipping = 0
    @total = 0 
    @est_tax = 0
    @order_total = 0
    @partner_order_id = rand(36**5).to_s(36)
    @stripe_id = nil
    @op_order_id = ""
    @payment_intent_id = ""
    @user_id_pvp = ""
    @address_id = ""
  

    # @address_obj = {
    #   # EasyPost params
    #   fname: response['results'][0]['name'],
    #   city: response['results'][0]['city'],
    #   state: response['results'][0]['state'],
    #   zip: response['results'][0]['zip'],
    #   street_address: response['results'][0]['first_line'],
    #   street_address2: response['results'][0]['second_line'],
    #   country: @country
    # }

    @address_obj = {
      # EasyPost params
      fname: response['name'],
      city: response['city'],
      state: response['state'],
      zip: response['zip'],
      street_address: response['first_line'],
      street_address2: response['second_line'],
      country: @country
    }
  
    #ship_to Params
    #@fname = @address_obj[:fname]
    @street_address = @address_obj[:street_address]
    @street_address2 = @address_obj[:street_address2]
    @city = @address_obj[:city]
    @zip = @address_obj[:zip]
    @state = @address_obj[:state]
    @fname, @lname = response['name'].split(' ')
   # @quantity = response['results'][0]['transactions'][0]['quantity']


    #grab_items_from_order(response)
    get_pvp_user
    easypostFn
    get_stripe_id
    process_payment

  end


  #might have to edit this function.
  #i assume that results[n] will contain n elements where n is the number of receipts.
  #now I woul have to iterate over these receipts.
  #depending on how many receipts a customer might have, this can get very long
  #sometimes we will iterate over a receipt that isn't for pvp, maybe find a way to identify pvp receipts to increase efficiency
  # also filter out receipts, so only 'ispaid=true' || 'status=paid' receipts get fetched.
  #check transaction db and to see if trans_id has already been used. if yes, do not execute.
  def init

  begin

   # #.json file
    #file = File.read('./receiptExample.json')
    #response = JSON.parse(file)
    #@response = response



    @integration = EtsyIntegrations.all 
    #@etsy_transaction = EtsyTransactions.all

    listing_ids_hash = {}
    etsy_transactions_hash = {}
    etsy_user_hash = {}
    @etsy_items = []

    @integration.each  { |row|
      row_listing_ids = row.listing_ids.split(',').map(&:to_i)

      etsy_user_hash[row] = row.etsy_user_id

      row_listing_ids.each { |listing_id|
        listing_ids_hash[listing_id] = row.shop_id
      }

      puts "rows: #{row.etsy_user_id}"
      puts "Acess token: #{row.access_token}"

      response = get_shop_receipts(row.etsy_user_id, row.access_token)
      @response = response

    #puts listing_ids_hash
    puts " "

    response['results'].each do |result|
      result['transactions'].each do |transaction|
        
        if listing_ids_hash[transaction["listing_id"]]

          previouslyPaid = EtsyTransactions.where(transaction_id: transaction['transaction_id'])

          puts "Checking to see if transaction_id: #{transaction['transaction_id']} has been paid for..."

          if(previouslyPaid != [])
            puts "Already paid for, moving to the next"
           
          else
            
            puts "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
            #puts " #{result}"
            puts "Found match!"
            puts "New transaction_id: #{transaction['transaction_id']}"
            puts "Using Listing_id: #{transaction["listing_id"]}"
            puts "From Shop_id: #{listing_ids_hash[transaction["listing_id"]]}"
            item = {
              listing_id: transaction['listing_id'],
              quantity: transaction['quantity'],
              transaction_id: transaction['transaction_id'],
              shop_id: listing_ids_hash[transaction["listing_id"]]
            }
  
  
            puts "Item(s) ready to be checked out::: #{item}"
            @etsy_items.append(item)
            puts "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
            puts " "
            populate_globals(result)

        end
        end
       end
    end
  }



    # @integration.each {|query|

    #   # real endpt
    #   # response = get_shop_receipts(query.etsy_user_id, query.access_token)
    #   # @response = response

    #   if response['error_description'] == "access token is expired"
    #     puts "refresh"
    #     refresh_token(query.etsy_user_id)
    #     # response = get_shop_receipts(query.etsy_user_id, query.access_token)
    #   else
       
    #   end
    
    #   listing_id = response['results'][0]['transactions'][0]['listing_id']
      

    #   listing_id_array = query.listing_ids.split(',').map(&:to_i)

    #   if listing_id_array.include?(listing_id)
    #     grab_items_from_order(response)
    #     puts "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
    #     puts 'Found match!'
    #     puts "Executing script with this listing_id: #{listing_id}"
    #     puts "Shop_id: #{query.shop_id}"
    #     puts "Username: #{query.username}"
    #     puts "Company_id: #{query.company_id}"
    #     puts "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"


    #     populate_globals(@response)

    #   else
    #     puts "no match... Iterating through the next listing_id"
    #   end

    #   # listing_id_array.each {|id|

    #   # if id.to_s.gsub(/[^0-9\.]/, '').to_i != listing_id
    #   #   puts 'no match... Iterating through the next listing_id'
    #   # else
    
    #   #   puts "::::::::::::"
    #   #   puts 'found match!'
    #   #   puts "Executing script with this listing_id: #{id.to_s.gsub(/[^0-9\.]/, '').to_i}"
    #   #   @listing_id = id.to_s.gsub(/[^0-9\.]/, '').to_i
    #   #   puts "Shop_id: #{query.shop_id}"
    #   #   puts "Username: #{query.username}"
    #   #   puts "Company_id: #{query.company_id}"
    #   #   puts "::::::::::::"
    #   #   populate_globals(response)


    #   # end
    
    #   # }
    # }
  rescue StandardError => e
  puts "error in loop::: #{e}"

  end

  end

  init

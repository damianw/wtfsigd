require "sinatra"
require 'koala'
require 'data_mapper'

enable :sessions
set :raise_errors, false
set :show_exceptions, false

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/users.db")  
class User  
  include DataMapper::Resource  
  property :id, Serial 
  property :name, String
  property :likes, Object
  property :ings, Object
  property :data, Object
  property :friends, Object
  property :nearbyfriends, Object
  property :closefriends, Object
  property :ignoredfriends, Object
  property :friendpref, Integer #0 for all friends, 1 for close friends, 2 for nearby friends
  property :objstate, Integer #0 for member of app, -1 for imported info
  #property :recentlymessaged, Object
end  
DataMapper.finalize.auto_upgrade!  

# Scope defines what permissions that we are asking the user to grant.
# In this example, we are asking for the ability to publish stories
# about using the app, access to what the user likes, and to be able
# to use their pictures.  You should rewrite this scope with whatever
# permissions your app needs.
# See https://developers.facebook.com/docs/reference/api/permissions/
# for a full list of permissions
FACEBOOK_SCOPE = 'user_likes,user_photos,user_photo_video_tags'
#User.raise_on_save_failure = true
#$queue = Array.new
#$queue_friends = Hash.new
#$queue_activities = Hash.new
def next_match (user)
    #while ($queue.size == 0)
    #end
    #puts "Found element in queue!"
    #user = $queue.pop
    matching_data = Array.new
    matching_ing = Array.new
    rand_friend = ""
    count = 0
    while matching_data.size == 0 && matching_ing.size == 0
      redirect "/youfuckingsuck" if count > 20
      rand_friend = get_random_friend(user)
      matching_ing = get_matching_ings(user, rand_friend)
      break if matching_ing.size > 0
      matching_data = get_matching_data(user, rand_friend)
      count = count + 1
    end
    #verb_activity_goal(rand_friend, matching_ing, matching_data)
    #user['friendid_queue'] << rand_friend['id']
    #if $queue_friends[user] == nil
      #$queue_friends[user] = Array.new
      #$queue_activities[user] = Array.new
      @rand_friend = rand_friend
    #end
    #$queue_friends[user] << rand_friend
    if matching_ing.size > 0
      @activity = matching_ing[rand(matching_ing.size)]
    else
      @activity = matching_data[rand(matching_data.size)]
    end
    #$queue_activities[user] << activity
    #user['activityid_queue'] << activityid
    #puts user.save
end

unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

before do
  # HTTPS redirect
  if settings.environment == :production && request.scheme != 'https'
    redirect "https://#{request.env['HTTP_HOST']}"
  end
end

helpers do
  def host
    request.env['HTTP_HOST']
  end

  def scheme
    request.scheme
  end

  def url_no_scheme(path = '')
    "//#{host}#{path}"
  end

  def url(path = '')
    "#{scheme}://#{host}#{path}"
  end

  def authenticator
    @authenticator ||= Koala::Facebook::OAuth.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], url("/auth/facebook/callback"))
  end

end

# the facebook session expired! reset ours and restart the process
error(Koala::Facebook::APIError) do
  session[:access_token] = nil
  redirect "/auth/facebook"
  #redirect "/login"
end

def get_closefriends 
  friends = Array.new
  @inbox = @graph.get_connections('me', 'inbox')
  @inbox.each do |mailitem|
    #puts mailitem["to"][1].to_s
    mailitem['to']['data'].each do |user|
      puts user.to_s
     if user['id'] != @my_fbuser['id']
      friends << user['id']
     end
    end
  end
  friends
end

def get_friends
  friends = Array.new
  @graph.get_connections('me', 'friends').each do |friend|
    friends << friend['id']
    #puts "NIGGERS: " + friend['id'].to_s
  end
  return friends
end

def get_nearbyfriends
  newsfeed = @graph.fql_query("SELECT id, page_id FROM location_post WHERE distance(latitude, longitude, '40.1112272999', '-88.225622899' ) < 10000")
  nearbyfriends = Array.new
  newsfeed.each do |page|
    nearbyfriends << @graph.get_object(page['id'])['from']['id']
  end
  nearbyfriends
end

def get_user(id = 'me')
  fbuser   = @graph.get_object(id)
  fbid = fbuser['id']
  puts "Getting FB user: " + fbid.to_s
  user = User.get(fbid)
  if (user != nil)
    puts "User exists."
    if id == 'me' && user['objstate'] == -1
      puts "User is skeleton. Filling..."
      user['nearbyfriends'] = get_nearbyfriends
      user['closefriends'] = get_closefriends
      user['friends'] = get_friends
      user['ignoredfriends'] = Array.new
      user['ignoredfriends'] << 0
      user['objstate'] = 0
    end
    user.save
  else
    puts "Creating new user: " + fbid.to_s
    user = User.new
    user['id'] = fbid
    user['name'] = fbuser['name']
    user['likes'] = get_likes(id)
    user['ings'] = get_ings(id)
    user['data'] = get_data(id)
    user['friendpref'] = 0
    if id == 'me'
      puts "User is self. Filling skeleton..."
      user['friends'] = get_friends
      user['nearbyfriends'] = get_nearbyfriends
      user['closefriends'] = get_closefriends
      user['ignoredfriends'] = Array.new
      user['ignoredfriends'] << 0
      user['objstate'] = 0
      user.save
    else
      user['objstate'] = -1
    end
    user.save
  end
  return user
end

def get_likes(id = 'me')
  @graph.get_connections(id, 'likes')
end

def get_ings(id = 'me')
  ings = Array.new
  likes = get_likes(id)
  likes.each do |like|
    if like['name'].end_with? 'ing'
      ings << like
    end
  end
  ings
end

def get_data(id = 'me')
  @graph.get_connections(id, 'activities')# + @graph.get_connections(id, 'music') + @graph.get_connections(id, 'movies')
end

def get_matching_data(user1, user2)
  matching_data = Array.new
  user1['data'].each do |activity|
    user2['data'].each do |activity2|
      matching_data << activity if activity['name'].downcase == activity2['name'].downcase
    end
  end
  matching_data
end

def get_matching_ings(user1, user2)
  matching_ings = Array.new
  user1['ings'].each do |activity|
    user2['ings'].each do |activity2|
      matching_ings << activity if activity['name'].downcase == activity2['name'].downcase
    end
  end
  matching_ings
end

def get_ignoredfriends(id = 'me')
  0 #TODO: figure out what the fuck i actually wanted to do
end

def get_random_friend(user)
  #puts user['friends']
  randf = User.new
  case user['friendpref']
  when 0 #for all friends
    randf = get_user(user['friends'][rand(user['friends'].size)])
  when 1 #for close friends
    randf = get_user(user['closefriends'][rand(user['closefriends'].size)])
  when 2 #for nearby friends
    user['nearbyfriends'] = get_nearbyfriends if user['nearbyfriends'] == nil
    randf = get_user(user['nearbyfriends'][rand(user['nearbyfriends'].size)])
  end
  randf
end

def queue(user)
  thread = Thread.new {next_match(user)}
  thread.run
  $queue << thread
  puts  $queue.size
end

get "/" do
  @graph  = Koala::Facebook::API.new(session[:access_token])
  #@graph = $graph
  @app  =  @graph.get_object(ENV["FACEBOOK_APP_ID"])
  if session[:access_token]

    @my_fbuser = @graph.get_object("me")
    @my_user = get_user("me")

    #puts @my_user['ignoredfriends'].to_s + " " + @my_user['closefriends'].to_s

    if session[:friendpref]
      @my_user['friendpref'] = session[:friendpref]
      session[:friendpref] = nil
      @my_user.save
    end
    if session[:toignore]
      @my_user['ignoredfriends'] << session[:toignore]
      session[:toignore] = nil
      @my_user.save
    end
    #$queue << @my_user << @my_user << @my_user << @my_user #for the hell of it
    #queue(@my_user)
    #queue(@my_user)
    #queue(@my_user)
      #pick a random friend

      #friends_a = @friends.to_a

      #we have a random friend... what can we do with them?
      #puts $queue_friends[@my_user].size.to_s
    #if $queue_friends[@my_user] == nil || $queue_friends[@my_user].size == 0
      next_match(@my_user)
    #  puts "derpity"
    #end
    #rand_friend = $queue_friends[@my_user].pop
    #activity = $queue_activities[@my_user].pop
    verb_activity_goal(@rand_friend, @activity)
    #@rand_friend = rand_friend
    session["friendid"] = @rand_friend['id']

    # for other data you can always run fql
    @friends_using_app = @graph.fql_query("SELECT uid, name, is_app_user, pic_square FROM user WHERE uid in (SELECT uid2 FROM friend WHERE uid1 = me()) AND is_app_user = 1")
    display_message
    session["friendpref"] = @my_user['friendpref']
    
    erb :home
  else
    erb :login
  end

  #erb :index
end

def verb_activity_goal(friend, activity)
  @activity = activity
  @verb = ""#" fucking go "
  puts @activity['category'] + ", " + @activity['name']
  @verb = " watching that fucking " if @activity['category'].include? "Movie"
  @verb = " listening to some fucking " if @activity['category'].include? "Music"
  @verb = "" if @activity['category'].include? "Interest"
  @activity['name'].downcase! if @activity['category'].include? "Interest"
  @goal = "You should" + @verb + @activity['category'] + "with" + friend['name'] + "."
  puts "You should" + @verb + @activity['name'] + " with " + friend['name'] + "."
end

get "/settings" do
  fix_instance_vars
  @my_user = get_user
  erb :settings
end

get "/login" do
  fix_instance_vars
  @app  =  @graph.get_object(480611415295029)
  erb :login
end

get "/fuckingclosefriends" do
  if session[:access_token]
    session['friendpref'] = 1
  end
  redirect "/"
end

get "/fuckingrandomasspeople" do
  if session[:access_token]
    session['friendpref'] = 0
  end
  redirect "/"
end

get "/fuckersnearby" do
  if session[:access_token]
    session['friendpref'] = 2
    fix_instance_vars
    @my_user = get_user
    @my_user['nearbyfriends'] = get_nearbyfriends
  end
  redirect "/"
end

get "/fuckthatguy" do
  if session[:friendid]
    fix_instance_vars
    @my_user = get_user
    @my_user['ignoredfriends'] = Array.new if @my_user['ignoredfriends'] == nil
    @my_user['ignoredfriends'] << session[:friendid]
    #session[:toignore] = session[:friendid]
  end
  redirect "/"
end

get "/youfuckingsuck" do
  session[:friendpref] = 0
  @message = "We found all fuck for that. Try a broader search. Dick."
  fix_instance_vars
  erb :message
end

# used to close the browser window opened to post to wall/send to friends
get "/close" do
  "<body onload='window.close();'/>"
end

get "/sign_out" do
  session[:access_token] = nil
  redirect '/'
end

get "/auth/facebook" do
  session[:access_token] = nil
  redirect authenticator.url_for_oauth_code(:permissions => FACEBOOK_SCOPE)
end

get '/auth/facebook/callback' do
	session[:access_token] = authenticator.get_access_token(params[:code])
	redirect '/'
end

def fix_instance_vars
  @graph = Koala::Facebook::API.new(session[:access_token])
  display_message
end

def display_message
  @displaying = "Searching "
  case session['friendpref']
  when 0
    @displaying += "all your fucking friends."
  when 1
    @displaying += "only those close best buddy fuckers that you love so much."
  when 2
    @displaying += "friends near your location. You creepy fucker."
  end
end

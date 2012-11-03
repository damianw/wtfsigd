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
  #property :fbid, Integer, :required => true, :key => true 
  property :likes, Object
  property :ings, Object
  property :data, Object
  property :friends, Object
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
end

get "/" do
  puts "derp1"
  # Get base API Connection
  @graph  = Koala::Facebook::API.new(session[:access_token])
  puts "derp2"
  # Get public details of current application
  @app  =  @graph.get_object(ENV["FACEBOOK_APP_ID"])
  puts "derp3"
  if session[:access_token]
    @user    = @graph.get_object("me")
    muser = User.get(:id => @user['id'])
    if (muser != nil)
      @friends = muser['friends']
      @my_likes = muser['likes']
      @my_data = muser['data']
      @my_ing = muser['ings']
    else
      @friends = @graph.get_connections('me', 'friends')
      #@photos  = @graph.get_connections('me', 'photos')
      @my_likes   = @graph.get_connections('me', 'likes')
      @my_data = @graph.get_connections('me', 'activities') + @graph.get_connections('me', 'movies') + @graph.get_connections('me', 'music')
      @my_ing = Array.new
      @my_likes.each do |like|
        if like['name'].end_with? 'ing'
          @my_ing << like
        end
      end
      muser = User.new#(id: @user['id'], likes: @my_likes, data: @my_data, ings: @my_ing, friends: @friends)
      muser.id = @user['id']
      muser.likes = @my_likes
      muser.data = @my_data
      muser.ings = @my_ing
      muser.friends = @friends
      puts muser.valid?
      muser.save
    end
    puts "MyINGs: " + @my_ing.size.to_s

    #pick a random friend
    friends_a = @friends.to_a
    #puts @rand_friend['name']
    
    # friendacts = @graph.get_connections(@rand_friend['id'], 'activities')#@rand_friend['id'], 'activities')
    # friendmovies = @graph.get_connections(@rand_friend['id'], 'movies')
    # friendmusic = @graph.get_connections(@rand_friend['id'], 'music')
    # friendinterests = @graph.get_connections(@rand_friend['id'], 'movies')
    # puts friendacts.size
    #we have a random friend... what can we do with them?
    matching_data = Array.new
    matching_ing = Array.new
    while matching_data.size == 0 && matching_ing.size == 0
      matching_data = Array.new
      randn = rand(friends_a.size)
      @rand_friend = friends_a[randn]
      puts "Trying " + @rand_friend['name']
      friend_data = @graph.get_connections(@rand_friend['id'], 'music') + @graph.get_connections(@rand_friend['id'], 'movies') + @graph.get_connections(@rand_friend['id'], 'activities')
      friend_likes = @graph.get_connections(@rand_friend['id'], 'likes')
      puts friend_data.size
      friend_ing = Array.new
      friend_likes.each do |like|
        if like['name'].end_with? 'ing'
          friend_ing << like
        end
      end
      @my_ing.each do |ing|
        friend_ing.each do |fing|
          if fing['name'] == ing['name']
            matching_ing << ing
          end
        end
      end
      break if matching_ing.size > 0
      puts "INGs: " + matching_ing.size.to_s
      @my_data.each do |like|
        friend_data.each do |flike|
          if flike['name'] == like['name']
            matching_data << like
          end
        end
        # if friend_data.include? like
        #   matching_data << like
        # end
      end
    end
    @verb = " fucking go "
    if matching_ing.size > 0
      @activity = matching_ing[rand(matching_ing.size)]
      @activity['name'].downcase!
    else
      @activity = matching_data[rand(matching_data.size)]
    end
    puts @activity['category'] + ", " + @activity['name']
    @verb = " watch that fucking " if @activity['category'].include? "Movie"
    @verb = " listen to some fucking " if @activity['category'].include? "Music"
    @verb = " fucking go " if @activity['category'].include? "Interest"
    @activity['category'].downcase! if @activity['category'].include? "Interest"
    @goal = "You should" + @verb + @activity['category'] + "with" + @rand_friend['name'] + "."
    puts "You should" + @verb + @activity['name'] + " with " + @rand_friend['name'] + "."

    # matching_data
    # matching_acts = Array.new
    # friendacts.each do |activity|
    #   @activities.each do |myact|
    #     if myact['name'].downcase == activity['name'].downcase
    #       matching_acts << activity
    #     end
    #   end
    # end

    # matching_movies = Array.new
    # friendmovies.each do |activity|
    #   @movies.each do |myact|
    #     if myact['name'].downcase == activity['name'].downcase
    #       matching_movies << activity
    #     end
    #   end
    # end

    

    #@yourgoal = matching_acts[rand(matching_acts.size)]
    #puts "You should go " + @yourgoal['name'] + " with " + @rand_friend['name'] + "."

    #@likes = @user.likes;

    # for other data you can always run fql
    @friends_using_app = @graph.fql_query("SELECT uid, name, is_app_user, pic_square FROM user WHERE uid in (SELECT uid2 FROM friend WHERE uid1 = me()) AND is_app_user = 1")
    erb :home
  else
    erb :index
  end

  #erb :index
end

# used by Canvas apps - redirect the POST to be a regular GET
post "/" do
  redirect "/"
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

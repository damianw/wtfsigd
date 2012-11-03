require "sinatra"
require 'koala'

enable :sessions
set :raise_errors, false
set :show_exceptions, false

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
  # Get base API Connection
  @graph  = Koala::Facebook::API.new(session[:access_token])

  # Get public details of current application
  @app  =  @graph.get_object(ENV["FACEBOOK_APP_ID"])

  if session[:access_token]
    @user    = @graph.get_object("me")
    @friends = @graph.get_connections('me', 'friends')
    @photos  = @graph.get_connections('me', 'photos')
    @likes   = @graph.get_connections('me', 'likes')
    @activities   = @graph.get_connections('me', 'activities')
    @movies   = @graph.get_connections('me', 'movies')
    @music   = @graph.get_connections('me', 'music')
    @my_data = @graph.get_connections('me', 'activities') + @graph.get_connections('me', 'movies') + @graph.get_connections('me', 'music')
    puts @likes.size
    puts @activities.size

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
    while matching_data.size == 0
      matching_data = Array.new
      randn = rand(friends_a.size)
      @rand_friend = friends_a[randn]
      puts "Trying " + @rand_friend['name']
      friend_data = @graph.get_connections(@rand_friend['id'], 'music') + @graph.get_connections(@rand_friend['id'], 'movies') + @graph.get_connections(@rand_friend['id'], 'activities')
      puts friend_data.size
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

    @activity = matching_data[rand(matching_data.size)]
    puts @activity['category']
    @verb = " watch that fucking " if @activity['category'].include? "Movie"
    @verb = " listen to some fucking " if @activity['category'].include? "Music"
    @verb = " fucking go " if @activity['category'].include? "Interest"
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
  end
  #erb :index
  erb :home
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

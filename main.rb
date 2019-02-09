require 'discordrb'
require 'pry'
require 'json'
require 'fuzzystringmatch'
require_relative 'services/discord_message_sender'
require_relative 'services/building_service'

class Main
  SECRETS = JSON.parse(File.read('secrets.json'))
  IMAGE_DIRECTORY_URL = SECRETS["image_directory_url"]

  bot = Discordrb::Commands::CommandBot.new(
    token: SECRETS["api_token"],
    client_id: SECRETS["api_client_id"],
    prefix: '~',
  )

  puts "This bot's invite URL is #{bot.invite_url}."
  puts 'Click on it to invite it to your server.'

  bot.ready() do |event|
    bot.game="~help"
  end

  bot.command(:help) do |event|
    fields = []
    fields << Discordrb::Webhooks::EmbedField.new(
      name: "General Commands",
      value:
        "**`~year <1-4, masters, alumni>`** - add your current academic status to your profile.\n"\
        "**`~purge <2-99>`** - remove the last `n` messages in channel (**admin only**)\n"\
        "**`~verify`** - verify your account\n"\
        "**`~help`** - return the help menu\n"\
        "\n\u200B"
    )

    fields << Discordrb::Webhooks::EmbedField.new(
      name: "Building Search Commands",
      value:
        "**`~whereis <buildingName || buildingCode>`** - return building details and location on map\n"\
        "**`~whereis list`** - return the list of all building codes and their associating names\n"
    )

    DiscordMessageSender.send_embedded(
      event.channel,
      title: "Help Menu",
      description: "Note: Arguments in <this format> do not require the '<', '>' characters\n\u200B",
      fields: fields,
    )
  end

  bot.command(:whereis) do |event|
    begin
      # Combine every word after 'whereis' for multi-word arguments (e.g. "Erie Hall")
      args = event.message.content.split(' ').drop(1).join(' ')
      if args == "list"
        building_list = BuildingService.gather_building_list
        DiscordMessageSender.send_embedded(
          event.channel,
          title: "Building List",
          fields: [
            Discordrb::Webhooks::EmbedField.new(name: "Codes", value: building_list[:codes], inline: true),
            Discordrb::Webhooks::EmbedField.new(name: "Full Names", value: building_list[:full_names], inline: true)
          ],
        )

      # If the argument matches a building
      elsif building_code = BuildingService.find_building(args)
        DiscordMessageSender.send_embedded(
          event.channel,
          title: "Building Search",
          image: Discordrb::Webhooks::EmbedImage.new(url: "#{IMAGE_DIRECTORY_URL}/#{building_code}.png"),
          description: BuildingService.get_building_name(building_code) + " (#{building_code})",
        )

      # Arguments did not match a command or building
      else
        DiscordMessageSender.send_embedded(
          event.channel,
          title: "Invalid Command or Building",
          description: ":bangbang: Building or command could not be found."\
            "\n\nTry using **~whereis list**",
        )
      end
    end
  end

  bot.command(:purge) do |event|
    return if event.server.nil?
    num_messages = event.message.content.split(' ').drop(1).join(' ').to_i + 1
    member = event.server.members.find { |member| member.id == event.user.id }

    if member.permission?(:administrator)
      if num_messages < 2 || num_messages > 100
        DiscordMessageSender.send_embedded(
          member.pm,
          title: "Invalid Usage",
          description: ":bangbang: Invalid number of messages to be removed.\n\n Correct usage: `~purge <2-99>`",
        )
        return
      end
      event.channel.prune(num_messages)
    else
      DiscordMessageSender.send_embedded(
        member.pm,
        title: "Insufficient Permissions",
        description: ":bangbang: You do not have permission to use this command.",
      )
      event.message.delete
    end
  end

  bot.command(:year) do |event|
    year = event.message.content.split(' ').drop(1).join(' ').upcase

    if event.server.nil?
      DiscordMessageSender.send_embedded(
        event.user.pm,
        title: "Invalid Usage",
        description: ":bangbang: Please use this command in the server.",
      )
      return
    end

    begin
      event.message.delete
    rescue Discordrb::Errors::NoPermission
      DiscordMessageSender.send_embedded(
        event.user.pm,
        title: "Error",
        description: ":bangbang: Bot has insufficient permissions to delete your command message.",
      )
    end

    server = event.server
    member = server.members.find { |member| member.id == event.user.id }

    if (member.roles.find { |role| role.name.upcase == "VERIFIED" }).nil?
      DiscordMessageSender.send_embedded(
        event.user.pm,
        title: "No Permission",
        description: ":bangbang: You must be verified to use this command.\n\n Verify using `~verify`",
      )
      return
    end

    year_roles = {
      "1" => server.roles.find { |role| role.name == "1st Year"},
      "2" => server.roles.find { |role| role.name == "2nd Year"},
      "3" => server.roles.find { |role| role.name == "3rd Year"},
      "4" => server.roles.find { |role| role.name == "4th Year"},
      "MASTERS" => server.roles.find { |role| role.name == "Masters"},
      "ALUMNI" => server.roles.find { |role| role.name == "Alumni"},
    }

    if !(year_roles.include? year)
      DiscordMessageSender.send_embedded(
        event.user.pm,
        title: "Invalid Usage",
        description: ":bangbang: Invalid option. Please select from: `#{year_roles.keys.to_s}`",
      )
      return
    end

    year_role = year_roles[year]

    if year_role
      begin
        member.add_role(year_role)
        previous_year_roles = member.roles.select { |role| (year_roles.values.include? role) && role != year_role }
        previous_year_roles.each { |role| member.remove_role(role) }
        DiscordMessageSender.send_embedded(
          member.pm,
          title: "Success",
          description: ":white_check_mark: Successfully added your year/status to your profile.",
        )
      rescue Discordrb::Errors::NoPermission
        DiscordMessageSender.send_embedded(
          member.pm,
          title: "Error",
          description: ":bangbang: Bot has insufficient permissions to modify your roles.",
        )
      end
    else
      DiscordMessageSender.send_embedded(
        member.pm,
        title: "Error",
        description: ":bangbang: Bot was unable to find the associating role in the server. Please notify admin.",
      )
    end
  end

  bot.run
end

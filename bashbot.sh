#!/bin/bash
echo $(tput bold)$(tput setaf 2)
cat <<EOF

                  ╦ ╦┌─┐┌─┐┬┌─┌─┐┬─┐┌─┐
                  ╠═╣├─┤│  ├┴┐├┤ ├┬┘└─┐
                  ╩ ╩┴ ┴└─┘┴ ┴└─┘┴└─└─┘
         ╔╗ ┌─┐┌─┐┬ ┬  ╔╦╗┬ ┬┬┌┬┐┌─┐┬ ┬  ╔╗ ┌─┐┌┬┐
         ╠╩╗├─┤└─┐├─┤   ║ ││││ │ │  ├─┤  ╠╩╗│ │ │
         ╚═╝┴ ┴└─┘┴ ┴   ╩ └┴┘┴ ┴ └─┘┴ ┴  ╚═╝└─┘ ┴

   Developped live : https://www.twitch.tv/videos/843197384

╔════════════════════════════════════════════════════════════╗
║ @tixlegeek                            https://tixlegeek.io ║
╠════════════════════════════════════════════════════════════╣
║  https://github.com/tixlegeek/hackersBashTwitchBot         ║
╚════════════════════════════════════════════════════════════╝
EOF
echo $(tput sgr0)
IRC_INPUT=ircinput
IRC_OUTPUT=ircoutput

IRC_HOST="irc.chat.twitch.tv"
IRC_PORT="6667"
IRC_NICK="tixlegeek"
IRC_USER="tixlegeek"
IRC_CHANNEL="#tixlegeek"
IRC_NOFLOOD_MAXWAIT=5
MQTT_ALLOW=false
MQTT_HOST="HOST"
MQTT_PORT="PORT"
MQTT_USER="USER"
MQTT_PASSWORD="PASSWORD"

# file ./pass countains the oauth token.
# visit: https://twitchapps.com/tmi/ to allow
IRC_PASS=$(cat ./pass)
# Log functions.
function irc_log(){
  echo $(tput setaf 3)"[i]"$(tput bold)"$@"$(tput sgr0)
}
function irc_in_log(){
  echo $(tput setaf 4)"[<]"$(tput bold)"$@"$(tput sgr0)
}
function irc_out_log(){
  echo $(tput setaf 5)"[>]"$(tput bold)"$@"$(tput sgr0)
}
function sys_log(){
  echo $(tput setaf 6)"[s]"$(tput bold)"$@"$(tput sgr0)
}
function bot_log(){
  echo $(tput setaf 2)"[B]"$(tput bold)"$@"$(tput sgr0)
}
function err_log(){
  echo $(tput setaf 1)"[x]"$(tput bold)"$@"$(tput sgr0)
}

# Randomized responses to commands
function irc_random_nope(){
  RANDOM_NOPE=$(shuf -n1 nopes)
  irc_send "PRIVMSG $CHANNEL : @$SENDER $RANDOM_NOPE"
}
function irc_random_ok(){
  RANDOM_OK=$(shuf -n1 oks)
  irc_send "PRIVMSG $CHANNEL : @$SENDER $RANDOM_NOPE"
}

function random_wait(){
    sleep $((1 + $RANDOM % $IRC_NOFLOOD_MAXWAIT))
}
# Quit function, called by trap
function IRC_QUIT (){
  sys_log "IRC quit"
  # Say bye to the server
  irc_send ":QUIT"

  # Kill subprocesses
  kill $IRC_READER &> /dev/null && sys_log "IRC_READER($IRC_READER) killed." || err_log "Could not kill IRC_READER"
  kill $IRC_WRITER &> /dev/null && sys_log "IRC_WRITER($IRC_WRITER) killed." || err_log "Could not kill IRC_WRITER"
  kill $IRC_BOT &> /dev/null && sys_log "IRC_BOT($IRC_BOT) killed." || err_log "Could not kill IRC_BOT"

  # Remove the named pipes.
  rm $IRC_INPUT &> /dev/null  && sys_log "IRC_INPUT($IRC_INPUT) fifo removed." || err_log "IRC_INPUT already gone."
  rm $IRC_OUTPUT &> /dev/null && sys_log "IRC_OUTPUT($IRC_OUTPUT) fifo removed." || err_log "IRC_OUTPUT already gone."
}

# Sends raw data to the socket
function irc_send(){
  random_wait
  echo "$@" >> $IRC_OUTPUT
}

# Bidirectionally bonded pipe
exec 3<>/dev/tcp/$IRC_HOST/$IRC_PORT || { err_log "Could not plug subsystem to &3 (no connection)"; exit 1;}
sys_log "Subsystem network plugged to &3"

# Catch SIGINT and call IRC_QUIT
trap IRC_QUIT SIGINT
sys_log "Trap set"

# Create INPUT and OUTPUT fifo
if [[ -p $IRC_INPUT ]]; then
  rm $IRC_INPUT
fi
mkfifo $IRC_INPUT
sys_log "NamedPipe $IRC_INPUT created"

if [[ -p $IRC_OUTPUT ]]; then
  rm $IRC_OUTPUT
fi
mkfifo $IRC_OUTPUT
sys_log "NamedPipe $IRC_OUTPUT created"

# READER
# reads socket and stores in IRC_INPUT
while true
do
  if read -r raw_input <&3 ;then
    irc_in_log "$raw_input"
    echo $raw_input > $IRC_INPUT
  fi
done &
IRC_READER=$!
sys_log "Reader PID: $IRC_READER"

# WRITER
# sends IRC_OUTPUT's content to the socket
while true
do
  if read -r raw_output <"$IRC_OUTPUT" ;then
    if [[ $raw_output == *"oauth"* ]]; then
      irc_out_log "> xxxxxxxxxxxxxxxxxxxxx"
    else
      irc_out_log "$raw_output"
    fi
    printf "%s\r\n" "$raw_output" >&3
  fi
done &
IRC_WRITER=$!
sys_log "Writer PID: $IRC_READER"

# Reads IRC_INPUT fifo, and parses IRC.
# This is the actual bot.
while true
do
  if read -r INPUT <"$IRC_INPUT";then
    # Removes the trailing \r (lf)
    # (IRC frames are separated with cr lf)
    INPUT=${INPUT%%$'\r'}
    # Set parameters to $INPUT (and tokenises it in $1-...)
    set -- $INPUT
    # When a message is received from the server ...
    case "$1" in
      # If the first word starts with ":", we catch sender's name.
      :*)
      # Removes everything after "!"
      SENDER=${1%%!*}
      # Remove the ":" at the beginning
      SENDER=${SENDER#:}
      # Shifts the argument list to the left ($1=$2...)
      shift
      ;;
    esac

    case "$@" in
      # Catch PING request and responds
      "PING "*)
      irc_send "PONG $2"
      ;;
      # Parses PRIVMSG
      "PRIVMSG "*)
        CHANNEL="$2"
        shift 2
        MSG="$@"
        MSG=${MSG#:}
        set -- $MSG
        case "$@" in

          # Reads a random line from file "insult"
          "!quote"*)
            RANDOM_INSULT=$(shuf -n1 quotes)
            bot_log "Command: $1 (random quote)"
            irc_send "PRIVMSG $CHANNEL : @$SENDER $RANDOM_INSULT"
          ;;

          # Sends MQTT request to some server...
          "!alert"*)
            bot_log "Command: $1 (mqtt alert)"
            if "$MQTT_ALLOW"; then
              mosquitto_pub -m "" -h "$MQTT_HOST" -p "$MQTT_PORT" -t "/twitch/alert" -u "$MQTT_USER" -P "$MQTT_PASSWORD"
              irc_random_ok
            else
              bot_log "[[ MQTT IS DISABLED ]] "
              irc_random_nope
            fi
          ;;

          *)
          bot_log "MSG: $MSG "
          ;;
        esac
      ;;
    esac
  fi
done &
IRC_BOT=$!
sys_log "Bot PID: $IRC_BOT"

sleep 1
irc_send "PASS $IRC_PASS"
irc_send "USER $IRC_USER 0 * :Twitch BashBot"
irc_send "NICK $IRC_USER"
irc_send "JOIN :$IRC_CHANNEL"

wait

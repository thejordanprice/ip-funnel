#!/bin/bash

IPTBL=/sbin/iptables
IPTBL_SAVE=/sbin/iptables-save
IPTBL_RESTORE=/sbin/iptables-restore
BACKUP_FILE=iptables_backup.txt

enable_ip_forwarding() {
  echo "1" > /proc/sys/net/ipv4/ip_forward
}

get_available_interfaces() {
  /sbin/ip -o link show | awk -F': ' '{print $2}'
}

rule_exists() {
  local rule="$1"
  $IPTBL_SAVE | grep -F -- "$rule" > /dev/null
  return $?
}

check_existing_rule() {
  local rule_pattern="$1"
  rule_exists "$rule_pattern"
  if [ $? -eq 0 ]; then
    echo "Skipping addition of duplicate rule: $rule_pattern"
    return 1
  else
    return 0
  fi
}

check_masquerade_rule() {
  rule_exists "-A POSTROUTING -j MASQUERADE"
  if [ $? -eq 0 ]; then
    echo "MASQUERADE rule already exists."
    return 1
  else
    return 0
  fi
}

add_rule() {
  local interfaces=$(get_available_interfaces)
  echo "Available interfaces: $interfaces"

  read -p "Enter input interface (default: ens18): " IF_IN
  IF_IN=${IF_IN:-ens18}

  # Validate if the entered interface exists
  if ! echo "$interfaces" | grep -qw "$IF_IN"; then
    echo "Interface '$IF_IN' is not valid or does not exist."
    return
  fi

  read -p "Enter input port (default: 80): " PORT_IN
  PORT_IN=${PORT_IN:-80}
  read -p "Enter destination IP: " IP_OUT
  read -p "Enter destination port (default: 8080): " PORT_OUT
  PORT_OUT=${PORT_OUT:-8080}

  enable_ip_forwarding

  PREROUTING_RULE="-t nat -A PREROUTING -i $IF_IN -p tcp --dport $PORT_IN -j DNAT --to-destination ${IP_OUT}:${PORT_OUT}"
  FORWARD_RULE="-A FORWARD -p tcp -d $IP_OUT --dport $PORT_OUT -j ACCEPT"

  check_existing_rule "$PREROUTING_RULE"
  if [ $? -eq 1 ]; then
    return
  fi

  check_existing_rule "$FORWARD_RULE"
  if [ $? -eq 1 ]; then
    return
  fi

  check_masquerade_rule
  if [ $? -eq 0 ]; then
    $IPTBL -t nat -A POSTROUTING -j MASQUERADE
  fi

  $IPTBL $PREROUTING_RULE
  $IPTBL $FORWARD_RULE

  echo "Rule added successfully."
}

list_rules() {
  echo "Current iptables rules:"
  $IPTBL_SAVE
}

delete_rule() {
  mapfile -t rules < <($IPTBL_SAVE | grep -E '^-A (PREROUTING|FORWARD|POSTROUTING)' | grep -v 'ufw')

  if [ ${#rules[@]} -eq 0 ]; then
    echo "No rules to delete."
    return
  fi

  echo "Select a rule to delete:"
  select rule in "${rules[@]}"; do
    if [[ -n "$rule" ]]; then
      echo "Deleting rule: $rule"
      
      chain=$(echo $rule | awk '{print $2}')
      rule_spec=$(echo $rule | cut -d' ' -f3-)

      if [[ $chain == "PREROUTING" || $chain == "POSTROUTING" ]]; then
        $IPTBL -t nat -D $chain $rule_spec
      else
        $IPTBL -D $chain $rule_spec
      fi

      echo "Rule deleted successfully."
      break
    else
      echo "Invalid selection."
    fi
  done
}

backup_rules() {
  echo "Backing up current iptables rules to $BACKUP_FILE..."
  $IPTBL_SAVE > $BACKUP_FILE
  echo "Backup completed."
}

restore_rules() {
  if [ ! -f $BACKUP_FILE ]; then
    echo "Backup file '$BACKUP_FILE' not found."
    return
  fi

  echo "Restoring iptables rules from $BACKUP_FILE..."
  $IPTBL_RESTORE < $BACKUP_FILE
  echo "Restore completed."
}

show_menu() {
  echo "IPTables Port Forwarding Script"
  echo "1. Add Rule"
  echo "2. Delete Rule"
  echo "3. List Rules"
  echo "4. Backup Rules"
  echo "5. Restore Rules"
  echo "6. Exit"
}

while true; do
  show_menu
  read -p "Enter your choice [1-6]: " choice
  case $choice in
    1) add_rule ;;
    2) delete_rule ;;
    3) list_rules ;;
    4) backup_rules ;;
    5) restore_rules ;;
    6) exit 0 ;;
    *) echo "Invalid option. Please select option 1, 2, 3, 4, 5, or 6." ;;
  esac
done

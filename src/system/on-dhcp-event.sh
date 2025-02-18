#!/bin/bash

# This script came from ubnt.com forum user "bradd" in the following post
# http://community.ubnt.com/t5/EdgeMAX/Automatic-DNS-resolution-of-DHCP-client-names/td-p/651311
# It has been modified by Ubiquiti to update the /etc/host file
# instead of adding to the CLI.
# Thanks to forum user "itsmarcos" for bug fix & improvements
# Thanks to forum user "ruudboon" for multiple domain fix
# Thanks to forum user "chibby85" for expire patch and static-mapping

if [ $# -lt 1 ]; then
  echo Invalid args
  logger -s -t on-dhcp-event "Invalid args \"$@\""
  exit 1
fi

action=$1
hostsd_client="/usr/bin/vyos-hostsd-client"

get_subnet_domain_name () {
  python3 <<EOF
from vyos.kea import kea_get_active_config
from vyos.utils.dict import dict_search_args

config = kea_get_active_config('4')
shared_networks = dict_search_args(config, 'arguments', f'Dhcp4', 'shared-networks')

found = False

if shared_networks:
  for network in shared_networks:
    for subnet in network[f'subnet4']:
      if subnet['id'] == $1:
        for option in subnet['option-data']:
          if option['name'] == 'domain-name':
            print(option['data'])
            found = True

        if not found:
          for option in network['option-data']:
            if option['name'] == 'domain-name':
              print(option['data'])
EOF
}

case "$action" in
  lease4_renew|lease4_recover)
    exit 0
    ;;

  lease4_release|lease4_expire|lease4_decline) # delete mapping for released/declined address
    client_ip=$LEASE4_ADDRESS
    $hostsd_client --delete-hosts --tag "dhcp-server-$client_ip" --apply
    exit 0
    ;;

  leases4_committed) # process committed leases (added/renewed/recovered)
    for ((i = 0; i < $LEASES4_SIZE; i++)); do
      client_ip_var="LEASES4_AT${i}_ADDRESS"
      client_mac_var="LEASES4_AT${i}_HWADDR"
      client_name_var="LEASES4_AT${i}_HOSTNAME"
      client_subnet_id_var="LEASES4_AT${i}_SUBNET_ID"

      client_ip=${!client_ip_var}
      client_mac=${!client_mac_var}
      client_name=${!client_name_var%.}
      client_subnet_id=${!client_subnet_id_var}

      if [ -z "$client_name" ]; then
          logger -s -t on-dhcp-event "Client name was empty, using MAC \"$client_mac\" instead"
          client_name=$(echo "host-$client_mac" | tr : -)
      fi

      client_domain=$(get_subnet_domain_name $client_subnet_id)

      if [[ -n "$client_domain" ]] && ! [[ $client_name =~ .*$client_domain$ ]]; then
        client_name="$client_name.$client_domain"
      fi

      $hostsd_client --add-hosts "$client_name,$client_ip" --tag "dhcp-server-$client_ip" --apply
    done

    exit 0
    ;;

  *)
    logger -s -t on-dhcp-event "Invalid command \"$1\""
    exit 1
    ;;
esac

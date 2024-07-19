#!/bin/bash
#Welcome to pre-post validation steps
#this script helps you to capture Traceroute and Ping for specific IP address or host
echo ""
echo "<<<<<[Pre-Post Validator Tool]>>>>>"
echo ""

#Jenkins Inputs #########################################################
Source_Partition_Number= ;
Destination_Partition_Number=$2
validationType=$3;
jiraPreSubtask=$4;
jiraPostSubtask=$5;
hydra_token=$6;
mysqlUser=$7; mysqlPass=$8; mysqlHost=${9}; mysqlDb=${10}
jiraUser=${11}; jiraPwd=${12}; jira_url=${13}; transition_id=${14}

#USER INPUT ########################################################
re='^VPN0[0-9]{4}$'
if ! [[ $Source_Partition_Number =~ $re ]] ; then
   echo "error: Invalid Input for Source Partition" >&2; exit 1
fi

#VARIABLES ##############################################################
preSrcSubnet="beforemigration_${Source_Partition_Number}_subnetlist.csv"
preDestSubnet="beforemigration_${Destination_Partition_Number}_subnetlist.csv"
postSrcSubnet="aftermigration_${Source_Partition_Number}_subnetlist.csv"
postDestSubnet="aftermigration_${Destination_Partition_Number}_subnetlist.csv"
currentDir=pwd
nowTime=$(date +%d-%b-%H_%M)
dhcp_flag="" #check for dhcp_reserved indicator

#FETCH PARTITION ID ###############################################
#Database Connection##
mysqlPort=6446
srcpartitionID=$(mysql -u $mysqlUser -p$mysqlPass -D $mysqlDb -h $mysqlHost --port=$mysqlPort -e "select distinct virtual_router_name_id from zcms_zones_on_hydra where virtual_router_number='$Source_Partition_Number';" -B --skip-column-names) || { echo "Database connectivity issue." ; exit 1; }
destpartitionID=$(mysql -u $mysqlUser -p$mysqlPass -D $mysqlDb -h $mysqlHost --port=$mysqlPort -e "select distinct virtual_router_name_id from zcms_zones_on_hydra where virtual_router_number='$Destination_Partition_Number';" -B --skip-column-names) || { echo "Database connectivity issue." ; exit 1; }


#FUNCTION#####################################################
getSubnetips() {
        local OLDIFS="$IFS" ; local SUB=${1/\/*/} ; local MASK=$(( 1 << ( 32 - ${1/*\//} )))
         IFS="."
                set -- $SUB
                IPS=$((0x$(printf "%02x%02x%02x%02x\n" $1 $2 $3 $4)))
        IFS="$OLDIFS"
        for ((N=0; N<MASK; N++))
        {
                VAL=$((IPS|N))

                printf "%d.%d.%d.%d\n"                  \
                        $(( (VAL >> 24) & 255 ))        \
                        $(( (VAL >> 16) & 255 ))        \
                        $(( (VAL >> 8 ) & 255 ))        \
                        $(( (VAL)       & 255 ))
        }
}


# Function to fetch issue list from JIRA
retrieve_network_json() {
    local PartitionName="$1"; local id="$2"; local hydra_token="$3";
    local output_file="./$PartitionName/temp/networks_${PartitionName}.json"
    curl -s https://hydra.gic.ericsson.se/api/9.0/partition/${id}?expand=networks \
            -H "Authorization: $hydra_token" -H "Accept:m application/json+v3" -o "$output_file"
    echo "$output_file"
}
retrieve_ips_json() {
    local PartitionName="$1"; local id="$2"; local hydra_token="$3";
    local output_file="./$PartitionName/temp/ips_${id}.json"
    curl -s https://hydra.gic.ericsson.se/api/9.0/network/${id}?expand=ips \
            -H "Authorization: $hydra_token" -H "Accept:m application/json+v3" -o "$output_file"
    echo "$output_file"
}
extract_network_info() {
        local json_data="$1"
        local PartitionName="$2"
        local output="$3"
        jq -r '.result[0].networks[] | [.id, .name, "\(.ipv4_start)/\(.ipv4_cidr)", "\(.ipv6_start)/\(.ipv6_cidr)"] | @csv' <<< "$json_data" >> "$PartitionName/$output"
    }
extract_network_ids() {
    local json_file="$1"
    local id=$(jq -r '.result[].networks[].id' "$json_file")
    echo "$id"
}
handle_response_code() {
    local component="$1"
    local response="$2"
    local jira_ticket="$3"
    # if [[ "$response" =~ "HTTP/2 20" ]] ; then
        echo "$component has been added/performed in $jira_ticket successfully!"
    # else
    #     echo "$component failed with error: $response"
    # fi
}
jira_update() {
    local response=""
    local component="$1"
    local jira_ticket="$2"
    local data="$3"

    response=$(curl -o- -s -i -D- -u "${jiraUser}:${jiraPwd}" -d "${data}" -s -X PUT -H "Content-Type: application/json" "${jira_url}/rest/api/2/issue/${jira_ticket}")
    handle_response_code $component $response $jira_ticket
}
jira_delete_attachments() {
    local jira_ticket="$1"
    # Get list of attachments
    local issue_details=$(curl -s -X GET -u "${jiraUser}:${jiraPwd}" \
        -H "Content-Type: application/json" "${jira_url}/rest/api/2/issue/${jira_ticket}?fields=attachment")
    # Extract attachment IDs
    local attachment_ids=$(echo "$issue_details" | jq -r '.fields.attachment[]?.id')
    #Delete Each attachment
    for attachment_id in $attachment_ids; do
        curl -s -X DELETE -u "${jiraUser}:${jiraPwd}" "${jira_url}/rest/api/2/attachment/$attachment_id"
        echo "Deleting all existing attachments if any..."
    done
}

jira_upload_attachments() {
        local component="$1";
        local jira_ticket="$2";
        shift 2 # Shift the positional parameters to access the file paths
        local response
        response=$(curl -D- -i -u "${jiraUser}:${jiraPwd}" -H "X-Atlassian-Token: nocheck" "$@" -s -X POST "${jira_url}/rest/api/2/issue/$jira_ticket/attachments")
        handle_response_code $component $response $jira_ticket
}
jira_closure() {
    local component="$1"
    local transition_id="$2"
    local jira_ticket="$3"
    local response
    response=$(curl -o- -i -D- -u "${jiraUser}:${jiraPwd}" -d "{\"transition\": {\"id\": \"$transition_id\"}}" -s -X POST -H "Content-Type: application/json" "${jira_url}/rest/api/2/issue/$jira_ticket/transitions")

    handle_response_code $component $response $jira_ticket
}
display_ipv4(){
    echo " Subnet Network Name:" $subnetName"  Subnet : "$subnetipv4
    echo " Total IP Address:" $ipv4_total
    echo " Total Host-Record(Hydra):" $ipv4_host
    echo " Total Host-Record Responding:" $ipv4_host_resp_yes
    echo " Reserved IP(Hydra):" $((ipv4_resv + ipv4_dhcp_resv))
    echo " Reserved IP Responding:" $((ipv4_resv_resp_yes + ipv4_dhcp_resv_resp_yes))
    echo " Non-Reserved IP(Hydra):" $ipv4_non_resv
    echo " Non-Reserved IP Responding:" $ipv4_non_resv_resp_yes
}
display_ipv6(){
    echo " Subnet Network Name:" $subnetName"  Subnet : "$subnetipv6
    echo " Total IP Address: $ipv6_total"
    echo " Total Host-Record(Hydra): $ipv6_host"
    echo " Total Host-Record Responding: $ipv6_host_resp_yes"
    echo " Reserved IP(Hydra): $ipv6_resv"
    echo " Reserved IP Responding: $ipv6_resv_resp_yes"
    echo " Non-Reserved IP(Hydra): $ipv6_non_resv"
    echo " Non-Reserved IP Responding: $ipv6_non_resv_resp_yes"
}
# Function to fetch issues matching the criteria and append label
jira_mark_as_migrated() {
    local source="$1"
    local destination="$2"
    local jql_query="Project=EDE+AND+labels=90p+AND+labels=${source}+AND+labels=${destination}"
    local start_at=0
    local max_results=50  # Adjust as per your needs
    local total_results=1

    while [[ $start_at -lt $total_results ]]; do
        local response=$(curl -s -u "${jiraUser}:${jiraPwd}" -X GET \
            "${jira_url}/rest/api/2/search?jql=${jql_query}&startAt=$start_at&maxResults=$max_results")
        total_results=$(echo "$response" | jq -r '.total')
        echo "Total tickets which belongs to migrated partition: $total_results"
        tasks=$(echo "$response" | jq -r '.issues[] | .key')
        for task_key in $tasks; do
            # Append label to each issue
            curl -s -u "${jiraUser}:${jiraPwd}" -X PUT \
                -H "Content-Type: application/json" \
                --data '{"update": {"labels": [{"add": "90p_migrated"}]}}' \
                "${jira_url}/rest/api/2/issue/$task_key"
        done
        start_at=$((start_at + max_results))
    done
    echo "All $total_results tickets has been marked as 90p_migrated "
}

##MAIN ##################################################################
echo "-----------------------------$validationType INPUTS---------------------------------"
echo -e "    Source         ----->          Destination"
echo -e "    "$Source_Partition_Number"       ----->          "$Destination_Partition_Number
echo -e "      "$srcpartitionID"         ----->           "$destpartitionID
echo -e ""
echo -e "Pre-Validation Jira Ticket:" $jiraPreSubtask
echo -e "Post-Validation Jira Ticket:" $jiraPostSubtask
echo "-----------------------------------------------------------------------------------"
mkdir -p $Source_Partition_Number $Source_Partition_Number/temp $Destination_Partition_Number $Destination_Partition_Number/temp
##PRE-VALIDATION########################################################
if [ $validationType == "Pre-validation" ]; then
	echo ""
    echo "[PREVALIDATION initiated....]"
    echo ""
    outputCSV=$Source_Partition_Number"_Prevalidation_$nowTime.csv"

    ###RETRIEVE PARTITION JSON#########################################
    srcNetworkJson=$(retrieve_network_json $Source_Partition_Number $srcpartitionID $hydra_token)
    destNetworkJson=$(retrieve_network_json $Destination_Partition_Number $destpartitionID $hydra_token)

    ##Fetch source network info
    extract_network_info "$(cat "${srcNetworkJson}")" "${Source_Partition_Number}" "${preSrcSubnet}"
    source_id=$(extract_network_ids "$srcNetworkJson")
    echo "$source_id" > $Source_Partition_Number/temp/ipIDs_$Source_Partition_Number.lst
    ##Fetch Destintion network info
    extract_network_info "$(cat "${destNetworkJson}")" "${Destination_Partition_Number}" "${preDestSubnet}"

    ##OUTFILE FORMAT/STYLING/HEADER###
    echo "NETWORK_NAME,IP_ADDRESS,FQDN,PRE_VALIDATION_PING" > $Source_Partition_Number/$outputCSV
    table1="\n||Subnet Name|| Subnet || Remark||\n"
    table2="\n||Subnet Name|| Subnet ||Total IPs||Total Host-Record(Hydra)|| Total Host-Record Responding|| Reserved IP(Hydra) || Reserved IP Responding || Non-Reserved IP ||Non-Reserved IP Responding||\n"
    table3="<style> .tb { border-collapse: collapse; } .tb th, .tb td { text-align: left; padding: 3px; border: solid 1px #777; } .yellow {background-color: yellow;} .aqua {background-color: Aquamarine;} .th1 {background-color: LightBlue;} .th2 {background-color: Lavender;} .th3 {background-color: Silver;} </style><table class="tb" border="1" ><tr><th>Subnet Name</th><th>Subnet</th><th>Total IPs</th><th class="th1">Total Host-Record(Hydra)</th><th class="th1">Total Host-Record Responding</th><th class="th2">Reserved IP(Hydra)</th><th class="th2">Reserved IP Responding</th><th class="th3">Non-Reserved IP</th><th class="th3">Non-Reserved IP Responding</th></tr>"

    ##TAKE ACTION ON EACH SUBNET
    for id in cat $Source_Partition_Number/temp/ipIDs_$Source_Partition_Number.lst
    do
        ipv4_total=0; ipv6_total=0;
        ipv4_host=0; ipv6_host=0; ipv4_host_resp_yes=0; ipv6_host_resp_yes=0;
		ipv4_resv=0; ipv6_resv=0; ipv4_resv_resp_yes=0; ipv6_resv_resp_yes=0;
        ipv4_dhcp_resv=0;ipv4_dhcp_resv_resp_yes=0;
        ipv4_non_resv=0; ipv6_non_resv=0; ipv4_non_resv_resp_yes=0; ipv6_non_resv_resp_yes=0;

        src_ips_json=cat $(retrieve_ips_json $Source_Partition_Number $id $hydra_token)

        while read -r SUBNET_INFO; do
            subnetName=$(echo "$SUBNET_INFO" | cut -d ',' -f2)
            ipv4Start=$(echo "$SUBNET_INFO" | cut -d ',' -f3)
            ipv4CIDR=$(echo "$SUBNET_INFO" | cut -d ',' -f4)
            ipv6Start=$(echo "$SUBNET_INFO" | cut -d ',' -f5)
            ipv6CIDR=$(echo "$SUBNET_INFO" | cut -d ',' -f6)

            if [[ $ipv4Start != 'null' ]]; then
                subnetipv4=$(echo "$ipv4Start""/""$ipv4CIDR")
                subnetlinkipv4="<a href=\"https://hydra.gic.ericsson.se/network/${id}/ipv4\">${subnetipv4}</a>"
                getSubnetips $subnetipv4 > $Source_Partition_Number/temp/ipaddress_$id.lst
            else
                subnetipv4=""
                subnetlinkipv4=""
            fi
            if [[ $ipv6Start != 'null' ]]; then
                subnetipv6=$(echo "$ipv6Start""/""$ipv6CIDR")
                subnetlinkipv6="<a href=\"https://hydra.gic.ericsson.se/network/${id}/ipv6\">${subnetipv6}</a>"
            else
                subnetipv6=""
                subnetlinkipv6=""
            fi

            echo "Network ["$id"]["$subnetName"]: ["${subnetipv4}"] ["${subnetipv6}"]"
            if echo "$subnetName" | grep -qE "Linknet|linknet"; then
                echo "      Skipping...Linknet subnet"
                echo ""
                if [[ $ipv4Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv4|Linknet (Not Moving)|\n"
                    table2+="|$subnetName|$subnetipv4|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|\n"
                    table3+="<tr><td><a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv4</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td></tr>"

                else
                    :
                fi
                if [[ $ipv6Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv6|Linknet (Not Moving)|\n"
                    table2+="|$subnetName|$subnetipv6|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|\n"
                    table3+="<tr><td><a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv6</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td></tr>"
                else
                    :
                fi
            else
                if [[ $ipv4Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv4|-|\n"
                else
                    :
                fi
                if [[ $ipv6Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv6|-|\n"
                else
                    :
                fi
                while read -r IP_INFO;
                do
                    ip_addr=$(echo "$IP_INFO" | cut -d ',' -f1)
                    dns_entry=$(echo "$IP_INFO" | cut -d ',' -f2)
                    dns_domain_id=$(echo "$IP_INFO" | cut -d ',' -f3)
                    ip_type_id=$(echo "$IP_INFO" | cut -d ',' -f4)
                    ip_role=$(echo "$IP_INFO" | cut -d ',' -f5)

                    #ADD DNS Domain to FQDN
                    if [[ $dns_entry == "null" ]]; then
                        :
                    else
                        if [[ $dns_domain_id = "11" ]]; then
                            dns_entry="$dns_entry.sero.gic.ericsson.se"
                        elif [[ $dns_domain_id = "4" ]]; then
                            dns_entry="$dns_entry.seli.gic.ericsson.se"
                        elif [[ $dns_domain_id = "75" ]]; then
                            dns_entry="$dns_entry.caot.gic.ericsson.se"
                        else
                            dns_entry="unknown"
                        fi
                    fi
                    #Identify the IP Type
                    if [[ $ip_type_id = "1" ]]; then
                        ip_type="Network"
                    elif [[ $ip_type_id = "2" ]]; then
                        ip_type="Host-Record"
                    elif [[ $ip_type_id = "3" ]]; then
                        ip_type="Router"
                    elif [[ $ip_type_id = "4" ]]; then
                        ip_type="Broadcast"
                    elif [[ $ip_type_id = "6" ]]; then
                        ip_type="DHCP_Reserved_Range"
                    elif [[ $ip_type_id = "7" ]]; then
                        ip_type="Reservation"
                    else
                        ip_type="Non-Reserved"
                    fi

                    #If condition for ip_role
                    if [[ $ip_role = "6" ]]; then
                        ip_type="Router"
                    fi

                    if [[ "$ip_type" = 'Network' || "$ip_type" == 'Router' || "$ip_type" == 'Broadcast' || "$ip_type" == 'Non-Reserved' ]]; then
                        echo "      Skipping... $ip_type Address: " $ip_addr
                        #remove the ips which are already in hydra
                        sed -i "/$ip_addr/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"
                        if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            ipv4_total=$((ipv4_total+1))  #counter
                        else
                            ipv6_total=$((ipv6_total+1))  #counter
                        fi
                    fi

                    #If condition to validate HOST RECORD ONLY
                    if [[ "$ip_type" == 'Host-Record' ]]; then
                        #remove the ips which are already in hydra
                        sed -i "/$ip_addr/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"

                        echo "      Validating [$ip_type] IP :" $ip_addr
                        ipv4_host=$((ipv4_host+1)) #counter
                        if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                                ipv4_total=$((ipv4_total+1))
                                ping -c 1 "$ip_addr" > /dev/null
                                if [ $? -eq 0 ]; then
                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                    ipv4_host_resp_yes=$((ipv4_host_resp_yes+1)) #counter
                                else
                                    if [[ $dns_entry == "null" ]]; then
                                        echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    else
                                        echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                        ping -c 1 "$dns_entry" > /dev/null
                                        if [ $? -eq 0 ]; then
                                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                            ipv4_host_resp_yes=$((ipv4_host_resp_yes+1)) #counter
                                        else
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        fi
                                    fi
                                fi
                            echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                        else
                            ipv6_total=$((ipv6_total+1))
                            ipv6_host=$((ipv6_host+1))  #counter
                            ping -c 1 "$ip_addr" > /dev/null
                                if [ $? -eq 0 ]; then
                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                    ipv6_host_resp_yes=$((ipv6_host_resp_yes+1)) #counter
                                else
                                    if [[ $dns_entry == "null" ]]; then
                                        echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    else
                                        echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                        ping -c 1 "$dns_entry" > /dev/null
                                        if [ $? -eq 0 ]; then
                                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                            ipv6_host_resp_yes=$((ipv6_host_resp_yes+1)) #counter
                                        else
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        fi
                                    fi
                                fi
                            echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                        fi
                    elif [[ "$ip_type" == 'Reservation' ]]; then
                            #remove the ips which are already in hydra
                            sed -i "/$ip_addr/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"
                            echo "      Validating [$ip_type] IP :" $ip_addr
                            if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                                    ipv4_total=$((ipv4_total+1))
                                    ipv4_resv=$((ipv4_resv+1)) #counter
                                    ping -c 1 "$ip_addr" > /dev/null
                                    if [ $? -eq 0 ]; then
                                        echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                        ipv4_resv_resp_yes=$((ipv4_resv_resp_yes+1))    #counter
                                    else
                                        if [[ $dns_entry == "null" ]]; then
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        else
                                            echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                            ping -c 1 "$dns_entry" > /dev/null
                                            if [ $? -eq 0 ]; then
                                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                                    ipv4_resv_resp_yes=$((ipv4_resv_resp_yes+1))    #counter
                                            else
                                                    echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                            fi
                                        fi
                                    fi
                                echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                            else
                                ipv6_total=$((ipv6_total+1))    #counter
                                ipv6_resv=$((ipv6_resv+1)) #counter
                                ping -c 1 "$ip_addr" > /dev/null
                                if [ $? -eq 0 ]; then
                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                    ipv6_resv_resp_yes=$((ipv6_resv_resp_yes+1))    #counter
                                else
                                    if [[ $dns_entry == "null" ]]; then
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    else
                                        echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                        ping -c 1 "$dns_entry" > /dev/null
                                        if [ $? -eq 0 ]; then
                                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                            ipv6_resv_resp_yes=$((ipv6_resv_resp_yes+1))    #counter
                                        else
                                                echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        fi
                                    fi
                                fi
                            echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                        fi
                    elif [[ "$ip_type" == 'DHCP_Reserved_Range' ]]; then
                            dhcp_flag="(DHCP Reserved)"
                        if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            if [ -s "$Source_Partition_Number/temp/ipaddress_$id.lst" ]; then
                                for i in cat $Source_Partition_Number/temp/ipaddress_$id.lst
                                do
                                    ipv4_total=$((ipv4_total+1))    #counter
                                    ipv4_dhcp_resv=$((ipv4_dhcp_resv+1))    #counter
                                    echo "      Validating [$ip_type] IP :" $i
                                    #remove the ips which are already in hydra
                                    sed -i "/$i/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"
                                    ping -c 1 "$i" > /dev/null
                                    if [ $? -eq 0 ]; then
                                        echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                        ipv4_dhcp_resv_resp_yes=$((ipv4_dhcp_resv_resp_yes+1))    #counter
                                    else
                                        echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    fi
                                echo "\"$subnetName\",\"$i\",\"No FQDN Present\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                                done
                            fi
                        fi
                    else
                        :
                    fi
                done < <(echo "${src_ips_json}" | jq -r '.result[].ips[] | "\(.ip_addr),\(.dns_entry),\(.dns_domain_id),\(.ip_type_id),\(.ip_role_id)"')

                #START######VALIDATION ALL NON MATCHED ipv4 FROM HYDRA"
                if [ -s "$Source_Partition_Number/temp/ipaddress_$id.lst" ]; then
                    for i in cat $Source_Partition_Number/temp/ipaddress_$id.lst
                    do
                        ip_type="Non-Reserved"
                        ipv4_total=$((ipv4_total+1))    #counter
                        ipv4_non_resv=$((ipv4_non_resv+1))    #counter
                        echo "      Validating [$ip_type] IP :" $i
                        ping -c 1 "$i" > /dev/null
                        if [ $? -eq 0 ]; then
                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                            ipv4_non_resv_resp_yes=$((ipv4_non_resv_resp_yes+1))    #counter
                        else
                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                        fi
                    echo "\"$subnetName\",\"$i\",\"No FQDN Present\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                    done
                else
                    echo "      Please Note: All machines are validated when compared to hydra"
                fi
                #END######VALIDATION ALL NON MATCHED IPS FROM HYDRA"
                echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
                if [[ $ipv4Start != 'null' ]]; then
                    display_ipv4
                    if [[ "$ipv4_host" != "$ipv4_host_resp_yes" ]]; then
                            indicator="<td class=\"yellow\">"
                    else
                            indicator="<td>"
                    fi
                    table2+="|$subnetName|$subnetipv4|$ipv4_total|$ipv4_host|$ipv4_host_resp_yes|$((ipv4_resv + ipv4_dhcp_resv))$dhcp_flag|$((ipv4_resv_resp_yes + ipv4_dhcp_resv_resp_yes))|$ipv4_non_resv|$ipv4_non_resv_resp_yes|\n"
                    table3+="<tr>$indicator<a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv4</td><td>$ipv4_total</td>$indicator$ipv4_host</td>$indicator$ipv4_host_resp_yes</td><td>$((ipv4_resv + ipv4_dhcp_resv))$dhcp_flag</td><td>$((ipv4_resv_resp_yes + ipv4_dhcp_resv_resp_yes))</td><td>$ipv4_non_resv</td><td>$ipv4_non_resv_resp_yes</td></tr>"

                else
                    :
                fi
                if [[ $ipv6Start != 'null' ]]; then
                    display_ipv6
                    if [[ "$ipv6_host" != "$ipv6_host_resp_yes" ]]; then
                      indicator="<td class=\"yellow\">"
                    else
                            indicator="<td>"
                    fi
                    table2+="|$subnetName|$subnetipv6|$ipv6_total|$ipv6_host|$ipv6_host_resp_yes|$((ipv6_resv + ipv6_dhcp_resv))|$((ipv6_resv_resp_yes + ipv6_dhcp_resv_resp_yes))|$ipv6_non_resv|$ipv6_non_resv_resp_yes|\n"
                    table3+="<tr>$indicator<a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv6</td><td>$ipv6_total</td>$indicator$ipv6_host</td>$indicator$ipv6_host_resp_yes</td><td>$ipv6_resv</td><td>$ipv6_resv_resp_yes</td><td>$ipv6_non_resv</td><td>$ipv6_non_resv_resp_yes</td></tr>"
                else
                    :
                fi
                echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
            fi
        done  < <(echo "$src_ips_json" | jq -r '.result[] | "\(.id),\(.name),\(.ipv4_start),\(.ipv4_cidr),\(.ipv6_start),\(.ipv6_cidr)"')
    done

    ######JIRAUPDATE-Description############################################################
    desc="This ticket is for tracking pre validation for the associated subnets.\\nBelow are the subnet details as follows: \\n"; desc+=${table1};
    jira_update "Description" ${jiraPreSubtask} "{\"fields\":{\"description\":\"$desc\"}}"

    ######JIRAUPDATE-Comments##############################################################
    cmts="XXXXXX[AUTOGENERATED BY JENKINS JOB]XXXXXX\n\nSummary:\n\nPrevalidation for $Source_Partition_Number has been performed for below subnets except linknet\n\n";
    cmts+=${table2}
    cmts+="\n\n Please find attached results for reference. \n\n Filename: $outputCSV"
    jira_update "Comments" ${jiraPreSubtask} "{\"update\": {\"comment\": [{\"add\": {\"body\": \"$cmts\"}}]}}"
    ######JIRA REFRESH/UPLOAD-Attachments##################################################
    jira_delete_attachments "${jiraPreSubtask}"

    jira_upload_attachments "Attachments" "${jiraPreSubtask}" \
    -F "file=@/$currentDir/$Source_Partition_Number/$outputCSV" \
    -F "file=@/$currentDir/$Source_Partition_Number/$preSrcSubnet" \
    -F "file=@/$currentDir/$Destination_Partition_Number/$preDestSubnet"

    ###CLOSURE OF JIRA TICKET#######
    jira_closure "Task Closure" $transition_id $jiraPreSubtask
    echo -e "Pre-Validation Completed! Please check below ticket:\n${jira_url}/browse/$jiraPreSubtask"

    rm -rf $Source_Partition_Number/temp $Destination_Partition_Number/temp
#############################################################################################
elif [ $validationType == "Post-validation" ]; then
	echo ""
    echo "[POSTVALIDATION initiated....]"
    echo ""
    outputCSV=$Source_Partition_Number"_Postvalidation_$nowTime.csv"

    response=$(curl -s -u ${jiraUser}:${jiraPwd} -H "Accept: application/json" "${jira_url}/rest/api/2/issue/$jiraPreSubtask?fields=attachment")
    ATTACHMENT_NAME=${preSrcSubnet}
    ATTACHMENT_ID=$(echo "$response" | jq -r --arg ATTACHMENT_NAME "$ATTACHMENT_NAME" '.fields.attachment[] | select(.filename == $ATTACHMENT_NAME) | .id')
    if [ -z "$ATTACHMENT_ID" ]; then
        echo "Attachment not found in pre validation JIRA $jiraPreSubtask with name: $ATTACHMENT_NAME"
        exit 1
    fi
    # Download the attachment
    DOWNLOAD_URL="${jira_url}/secure/attachment/$ATTACHMENT_ID/$ATTACHMENT_NAME"
    curl -s -u ${jiraUser}:${jiraPwd} -H "Accept: application/json" -O "$DOWNLOAD_URL"
    mv $ATTACHMENT_NAME  $Source_Partition_Number/$ATTACHMENT_NAME
    echo "Downloaded $ATTACHMENT_NAME from $jiraPreSubtask"

    cut -d',' -f1 "$Source_Partition_Number/$ATTACHMENT_NAME" > "$Source_Partition_Number/temp/ipIDs_$Source_Partition_Number.lst"

    ########EXTRACT NETWORK DETAILS FOR SRC & TARGET PARTITION##############################
    srcNetworkJson=$(retrieve_network_json $Source_Partition_Number $srcpartitionID $hydra_token)
    destNetworkJson=$(retrieve_network_json $Destination_Partition_Number $destpartitionID $hydra_token)

    ##Fetch Source network info
    extract_network_info "$(cat "${srcNetworkJson}")" "${Source_Partition_Number}" "${postSrcSubnet}"
    source_id=$(extract_network_ids "$srcNetworkJson")
    ##Fetch Destintion network info
    extract_network_info "$(cat "${destNetworkJson}")" "${Destination_Partition_Number}" "${postDestSubnet}"

    ###
    echo "NETWORK_NAME,IP_ADDRESS,FQDN,POST_VALIDATION_PING" > $Source_Partition_Number/$outputCSV
    table1="\n||Subnet Name|| Subnet || Remark||\n"
    table2="\n||Subnet Name|| Subnet ||Total IPs||Total Host-Record(Hydra)|| Total Host-Record Responding|| Reserved IP(Hydra) || Reserved IP Responding || Non-Reserved IP ||Non-Reserved IP Responding||\n"
    table3="<style> .tb { border-collapse: collapse; } .tb th, .tb td { text-align: left; padding: 3px; border: solid 1px #777; } .yellow {background-color: yellow;} .aqua {background-color: Aquamarine;} .th1 {background-color: LightBlue;} .th2 {background-color: Lavender;} .th3 {background-color: Silver;} </style><table class="tb" border="1" ><tr><th>Subnet Name</th><th>Subnet</th><th>Total IPs</th><th class="th1">Total Host-Record(Hydra)</th><th class="th1">Total Host-Record Responding</th><th class="th2">Reserved IP(Hydra)</th><th class="th2">Reserved IP Responding</th><th class="th3">Non-Reserved IP</th><th class="th3">Non-Reserved IP Responding</th></tr>"

    ##TAKE ACTION ON EACH SUBNET
    for id in cat $Source_Partition_Number/temp/ipIDs_$Source_Partition_Number.lst
    do
        ipv4_total=0; ipv6_total=0;
        ipv4_host=0; ipv6_host=0; ipv4_host_resp_yes=0; ipv6_host_resp_yes=0;
		ipv4_resv=0; ipv6_resv=0; ipv4_resv_resp_yes=0; ipv6_resv_resp_yes=0;
        ipv4_dhcp_resv=0;ipv4_dhcp_resv_resp_yes=0;
        ipv4_non_resv=0; ipv6_non_resv=0; ipv4_non_resv_resp_yes=0; ipv6_non_resv_resp_yes=0;

        src_ips_json=cat $(retrieve_ips_json $Source_Partition_Number $id $hydra_token)

        while read -r SUBNET_INFO; do
            subnetName=$(echo "$SUBNET_INFO" | cut -d ',' -f2)
            ipv4Start=$(echo "$SUBNET_INFO" | cut -d ',' -f3)
            ipv4CIDR=$(echo "$SUBNET_INFO" | cut -d ',' -f4)
            ipv6Start=$(echo "$SUBNET_INFO" | cut -d ',' -f5)
            ipv6CIDR=$(echo "$SUBNET_INFO" | cut -d ',' -f6)

            if [[ $ipv4Start != 'null' ]]; then
                subnetipv4=$(echo "$ipv4Start""/""$ipv4CIDR")
                subnetlinkipv4="<a href=\"https://hydra.gic.ericsson.se/network/${id}/ipv4\">${subnetipv4}</a>"
                getSubnetips $subnetipv4 > $Source_Partition_Number/temp/ipaddress_$id.lst
            else
                subnetipv4=""
                subnetlinkipv4=""
            fi
            if [[ $ipv6Start != 'null' ]]; then
                subnetipv6=$(echo "$ipv6Start""/""$ipv6CIDR")
                subnetlinkipv6="<a href=\"https://hydra.gic.ericsson.se/network/${id}/ipv6\">${subnetipv6}</a>"
            else
                subnetipv6=""
                subnetlinkipv6=""
            fi

            echo "Network ["$id"]["$subnetName"]: ["${subnetipv4}"] ["${subnetipv6}"]"
            if echo "$subnetName" | grep -qE "Linknet|linknet"; then
                echo "      Skipping...Linknet subnet"
                echo ""
                if [[ $ipv4Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv4|Linknet (Not Moving)|\n"
                    table2+="|$subnetName|$subnetipv4|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|\n"
                    table3+="<tr><td><a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv4</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td></tr>"

                else
                    :
                fi
                if [[ $ipv6Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv6|Linknet (Not Moving)|\n"
                    table2+="|$subnetName|$subnetipv6|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|Skipped|\n"
                    table3+="<tr><td><a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv6</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td><td>Skipped</td></tr>"
                else
                    :
                fi
            else
                if [[ $ipv4Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv4|-|\n"
                else
                    :
                fi
                if [[ $ipv6Start != 'null' ]]; then
                    table1+="|$subnetName|$subnetipv6|-|\n"
                else
                    :
                fi
                while read -r IP_INFO;
                do
                    ip_addr=$(echo "$IP_INFO" | cut -d ',' -f1)
                    dns_entry=$(echo "$IP_INFO" | cut -d ',' -f2)
                    dns_domain_id=$(echo "$IP_INFO" | cut -d ',' -f3)
                    ip_type_id=$(echo "$IP_INFO" | cut -d ',' -f4)
                    ip_role=$(echo "$IP_INFO" | cut -d ',' -f5)

                    #ADD DNS Domain to FQDN
                    if [[ $dns_entry == "null" ]]; then
                        :
                    else
                        if [[ $dns_domain_id = "11" ]]; then
                            dns_entry="$dns_entry.sero.gic.ericsson.se"
                        elif [[ $dns_domain_id = "4" ]]; then
                            dns_entry="$dns_entry.seli.gic.ericsson.se"
                        elif [[ $dns_domain_id = "75" ]]; then
                            dns_entry="$dns_entry.caot.gic.ericsson.se"
                        else
                            dns_entry="unknown"
                        fi
                    fi
                    #Identify the IP Type
                    if [[ $ip_type_id = "1" ]]; then
                        ip_type="Network"
                    elif [[ $ip_type_id = "2" ]]; then
                        ip_type="Host-Record"
                    elif [[ $ip_type_id = "3" ]]; then
                        ip_type="Router"
                    elif [[ $ip_type_id = "4" ]]; then
                        ip_type="Broadcast"
                    elif [[ $ip_type_id = "6" ]]; then
                        ip_type="DHCP_Reserved_Range"
                    elif [[ $ip_type_id = "7" ]]; then
                        ip_type="Reservation"
                    else
                        ip_type="Non-Reserved"
                    fi

                    #If condition for ip_role
                    if [[ $ip_role = "6" ]]; then
                        ip_type="Router"
                    fi

                    if [[ "$ip_type" = 'Network' || "$ip_type" == 'Router' || "$ip_type" == 'Broadcast' || "$ip_type" == 'Non-Reserved' ]]; then
                        echo "      Skipping... $ip_type Address: " $ip_addr
                        #remove the ips which are already in hydra
                        sed -i "/$ip_addr/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"
                        if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            ipv4_total=$((ipv4_total+1))  #counter
                        else
                            ipv6_total=$((ipv6_total+1))  #counter
                        fi
                    fi

                    #If condition to validate HOST RECORD ONLY
                    if [[ "$ip_type" == 'Host-Record' ]]; then
                        #remove the ips which are already in hydra
                        sed -i "/$ip_addr/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"

                        echo "      Validating [$ip_type] IP :" $ip_addr
                        ipv4_host=$((ipv4_host+1)) #counter
                        if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                                ipv4_total=$((ipv4_total+1))
                                ping -c 1 "$ip_addr" > /dev/null
                                if [ $? -eq 0 ]; then
                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                    ipv4_host_resp_yes=$((ipv4_host_resp_yes+1)) #counter
                                else
                                    if [[ $dns_entry == "null" ]]; then
                                        echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    else
                                        echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                        ping -c 1 "$dns_entry" > /dev/null
                                        if [ $? -eq 0 ]; then
                                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                            ipv4_host_resp_yes=$((ipv4_host_resp_yes+1)) #counter
                                        else
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        fi
                                    fi
                                fi
                            echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                        else
                            ipv6_total=$((ipv6_total+1))
                            ipv6_host=$((ipv6_host+1))  #counter
                            ping -c 1 "$ip_addr" > /dev/null
                                if [ $? -eq 0 ]; then
                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                    ipv6_host_resp_yes=$((ipv6_host_resp_yes+1)) #counter
                                else
                                    if [[ $dns_entry == "null" ]]; then
                                        echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    else
                                        echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                        ping -c 1 "$dns_entry" > /dev/null
                                        if [ $? -eq 0 ]; then
                                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                            ipv6_host_resp_yes=$((ipv6_host_resp_yes+1)) #counter
                                        else
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        fi
                                    fi
                                fi
                            echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                        fi
                    elif [[ "$ip_type" == 'Reservation' ]]; then
                            #remove the ips which are already in hydra
                            sed -i "/$ip_addr/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"
                            echo "      Validating [$ip_type] IP :" $ip_addr
                            if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                                    ipv4_total=$((ipv4_total+1))
                                    ipv4_resv=$((ipv4_resv+1)) #counter
                                    ping -c 1 "$ip_addr" > /dev/null
                                    if [ $? -eq 0 ]; then
                                        echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                        ipv4_resv_resp_yes=$((ipv4_resv_resp_yes+1))    #counter
                                    else
                                        if [[ $dns_entry == "null" ]]; then
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        else
                                            echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                            ping -c 1 "$dns_entry" > /dev/null
                                            if [ $? -eq 0 ]; then
                                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                                    ipv4_resv_resp_yes=$((ipv4_resv_resp_yes+1))    #counter
                                            else
                                                    echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                            fi
                                        fi
                                    fi
                                echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                            else
                                ipv6_total=$((ipv6_total+1))    #counter
                                ipv6_resv=$((ipv6_resv+1)) #counter
                                ping -c 1 "$ip_addr" > /dev/null
                                if [ $? -eq 0 ]; then
                                    echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                    ipv6_resv_resp_yes=$((ipv6_resv_resp_yes+1))    #counter
                                else
                                    if [[ $dns_entry == "null" ]]; then
                                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    else
                                        echo "            ....Not Responding. Validating its FQDN :"$dns_entry
                                        ping -c 1 "$dns_entry" > /dev/null
                                        if [ $? -eq 0 ]; then
                                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                            ipv6_resv_resp_yes=$((ipv6_resv_resp_yes+1))    #counter
                                        else
                                                echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                        fi
                                    fi
                                fi
                            echo "\"$subnetName\",\"$ip_addr\",\"$dns_entry\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                        fi
                    elif [[ "$ip_type" == 'DHCP_Reserved_Range' ]]; then
                            dhcp_flag="(DHCP Reserved)"
                        if [[ "$ip_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            if [ -s "$Source_Partition_Number/temp/ipaddress_$id.lst" ]; then
                                for i in cat $Source_Partition_Number/temp/ipaddress_$id.lst
                                do
                                    ipv4_total=$((ipv4_total+1))    #counter
                                    ipv4_dhcp_resv=$((ipv4_dhcp_resv+1))    #counter
                                    echo "      Validating [$ip_type] IP :" $i
                                    #remove the ips which are already in hydra
                                    sed -i "/$i/d" "$Source_Partition_Number/temp/ipaddress_$id.lst"
                                    ping -c 1 "$i" > /dev/null
                                    if [ $? -eq 0 ]; then
                                        echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                                        ipv4_dhcp_resv_resp_yes=$((ipv4_dhcp_resv_resp_yes+1))    #counter
                                    else
                                        echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                                    fi
                                echo "\"$subnetName\",\"$i\",\"No FQDN Present\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                                done
                            fi
                        fi
                    else
                        :
                    fi
                done < <(echo "$src_ips_json" | jq -r '.result[].ips[] | "\(.ip_addr),\(.dns_entry),\(.dns_domain_id),\(.ip_type_id),\(.ip_role_id)"')

                #START######VALIDATION ALL NON MATCHED ipv4 FROM HYDRA"
                if [ -s "$Source_Partition_Number/temp/ipaddress_$id.lst" ]; then
                    for i in cat $Source_Partition_Number/temp/ipaddress_$id.lst
                    do
                        ip_type="Non-Reserved"
                        ipv4_total=$((ipv4_total+1))    #counter
                        ipv4_non_resv=$((ipv4_non_resv+1))    #counter
                        echo "      Validating [$ip_type] IP :" $i
                        ping -c 1 "$i" > /dev/null
                        if [ $? -eq 0 ]; then
                            echo "Yes" > $Source_Partition_Number/temp/pingResponse.lst
                            ipv4_non_resv_resp_yes=$((ipv4_non_resv_resp_yes+1))    #counter
                        else
                            echo "No" > $Source_Partition_Number/temp/pingResponse.lst
                        fi
                    echo "\"$subnetName\",\"$i\",\"No FQDN Present\",\"cat $Source_Partition_Number/temp/pingResponse.lst\"" >> $Source_Partition_Number/$outputCSV
                    done
                else
                    echo "      Please Note: All machines are validated when compared to hydra"
                fi
                #END######VALIDATION ALL NON MATCHED IPS FROM HYDRA"
                echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
                if [[ $ipv4Start != 'null' ]]; then
                    display_ipv4
                    if [[ "$ipv4_host" != "$ipv4_host_resp_yes" ]]; then

                            indicator="<td class=\"yellow\">"
                    else
                            indicator="<td>"
                    fi
                    table2+="|$subnetName|$subnetipv4|$ipv4_total|$ipv4_host|$ipv4_host_resp_yes|$((ipv4_resv + ipv4_dhcp_resv))$dhcp_flag|$((ipv4_resv_resp_yes + ipv4_dhcp_resv_resp_yes))|$ipv4_non_resv|$ipv4_non_resv_resp_yes|\n"
                    table3+="<tr>$indicator<a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv4</td><td>$ipv4_total</td>$indicator$ipv4_host</td>$indicator$ipv4_host_resp_yes</td><td>$((ipv4_resv + ipv4_dhcp_resv))$dhcp_flag</td><td>$((ipv4_resv_resp_yes + ipv4_dhcp_resv_resp_yes))</td><td>$ipv4_non_resv</td><td>$ipv4_non_resv_resp_yes</td></tr>"

                else
                    :
                fi
                if [[ $ipv6Start != 'null' ]]; then
                    display_ipv6
                    if [[ "$ipv6_host" != "$ipv6_host_resp_yes" ]]; then
                            indicator="<td class=\"yellow\">"
                    else
                            indicator="<td>"
                    fi
                    table2+="|$subnetName|$subnetipv6|$ipv6_total|$ipv6_host|$ipv6_host_resp_yes|$((ipv6_resv + ipv6_dhcp_resv))|$((ipv6_resv_resp_yes + ipv6_dhcp_resv_resp_yes))|$ipv6_non_resv|$ipv6_non_resv_resp_yes|\n"
                    table3+="<tr>$indicator<a href=\"https://hydra.gic.ericsson.se/network/${id}/view\">$subnetName</a></td><td>$subnetlinkipv6</td><td>$ipv6_total</td>$indicator$ipv6_host</td>$indicator$ipv6_host_resp_yes</td><td>$ipv6_resv</td><td>$ipv6_resv_resp_yes</td><td>$ipv6_non_resv</td><td>$ipv6_non_resv_resp_yes</td></tr>"
                else
                    :
                fi
                echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
            fi
        done  < <(echo "$src_ips_json" | jq -r '.result[] | "\(.id),\(.name),\(.ipv4_start),\(.ipv4_cidr),\(.ipv6_start),\(.ipv6_cidr)"')
    done

    echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    ######JIRAUPDATE-Description############################################################
    desc="This ticket is for tracking post validation for the associated subnets.\\nBelow are the subnet details as follows: \\n"; desc+=${table1};
    jira_update "Description" ${jiraPostSubtask} "{\"fields\":{\"description\":\"$desc\"}}"

    ######JIRAUPDATE-Comments##############################################################
    cmts="XXXXXX[AUTOGENERATED BY JENKINS JOB]XXXXXX\n\nSummary:\n\nPostvalidation for $Source_Partition_Number has been performed for below subnets \n\n ${table2} \n\n Please find attached results for reference. \n\n Filename: $outputCSV \n\n Kindly compare this file with pre-validation file mentioned in ${jira_url}/browse/$jiraPreSubtask and share the results if any."
    jira_update "Comments" ${jiraPostSubtask} "{\"update\": {\"comment\": [{\"add\": {\"body\": \"$cmts\"}}]}}"

    ######JIRA REFRESH/UPLOAD-Attachments##################################################
    jira_delete_attachments "${jiraPostSubtask}"

    jira_upload_attachments "Attachments" "${jiraPostSubtask}" \
    -F "file=@/$currentDir/$Source_Partition_Number/$outputCSV" \
    -F "file=@/$currentDir/$Source_Partition_Number/$preSrcSubnet" \
    -F "file=@/$currentDir/$Source_Partition_Number/$postSrcSubnet"\
    -F "file=@/$currentDir/$Destination_Partition_Number/$postDestSubnet"

    ###CLOSURE OF JIRA TICKET#######
    jira_closure "Task Closure" $transition_id "$jiraPostSubtask"
    echo -e "Post-Validation Completed! Please check below ticket:\n${jira_url}/browse/$jiraPostSubtask"

    rm -rf $Source_Partition_Number/temp $Destination_Partition_Number/temp

    ##Mark subtask as label 90p_migrated
    source=$(echo $Source_Partition_Number | sed 's/[^0-9]*0*\([1-9][0-9]*\).*/\1/')
    destination=$(echo $Destination_Partition_Number | sed 's/[^0-9]*0*\([1-9][0-9]*\).*/\1/')
    jira_mark_as_migrated $source $destination
else
    echo "Invalid argument passed for validation type."
    exit 1
fi

table3+="</table>"
echo "${table3}" > emailtemplate.txt
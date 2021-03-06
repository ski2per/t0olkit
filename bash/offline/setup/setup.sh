#!/bin/bash

function colorful_echo {
    RED='\E[31m'
    GREEN='\E[32m'
    YELLOW='\E[33m'
    BLUE='\E[34m'
    WHITE='\E[38m'
    END='\033[0m'

    msg=$1
    color=$2
    case $color in
        "red")
            current_color=$RED
            ;;
        "green")
            current_color=$GREEN
            ;;
        "yellow")
            current_color=$YELLOW
            ;;
        "blue")
            current_color=$BLUE
            ;;
        "*")
            current_color=$WHITE
            ;;
    esac

    echo -e "$current_color$msg$END"

}

function echo_stage {
    stage_msg=$1

    # Output border character
    stage_color="green"
    border_char="="
    num='72'
    border=$(printf "%-${num}s" "${border_char}")

    echo ""
    echo ""
    colorful_echo "${border// /${border_char}}" $stage_color
    colorful_echo "${stage_msg}" $stage_color
    colorful_echo "${border// /${border_char}}" $stage_color
}

function echo_banner {
    echo -e "\e[33m   ____   __  __ _ _               _____      _               \e[0m";
    echo -e "\e[33m  / __ \ / _|/ _| (_)             / ____|    | |              \e[0m";
    echo -e "\e[33m | |  | | |_| |_| |_ _ __   ___  | (___   ___| |_ _   _ _ __  \e[0m";
    echo -e "\e[33m | |  | |  _|  _| | | '_ \ / _ \  \___ \ / _ \ __| | | | '_ \ \e[0m";
    echo -e "\e[33m | |__| | | | | | | | | | |  __/  ____) |  __/ |_| |_| | |_) |\e[0m";
    echo -e "\e[33m  \____/|_| |_| |_|_|_| |_|\___| |_____/ \___|\__|\__,_| .__/ \e[0m";
    echo -e "\e[33m                                                       | |    \e[0m";
    echo -e "\e[33m                                                       |_|    \e[0m";
}

function echo_banner_done {
    echo -e "\e[33m  _____   ____  _   _ ______ \e[0m";
    echo -e "\e[33m |  __ \ / __ \| \ | |  ____|\e[0m";
    echo -e "\e[33m | |  | | |  | |  \| | |__   \e[0m";
    echo -e "\e[33m | |  | | |  | | . \` |  __|  \e[0m";
    echo -e "\e[33m | |__| | |__| | |\  | |____ \e[0m";
    echo -e "\e[33m |_____/ \____/|_| \_|______|\e[0m";
    echo -e "\e[33m                             \e[0m";
}


function setup_fabric {
    FABRIC_DEPLOYER="$BASE_DIR/fabric_deployer"
    MAPPING_DIR="$FABRIC_DEPLOYER/mappings"
    MAPPING_TPL="$MAPPING_DIR/mapping.tpl"
    NODE_MAPPING="$MAPPING_DIR/node_mapping.json"
    FABIRC_PLATFORM=`grep '"FABIRC_PLATFORM_BASE"' $MAPPING_TPL | awk -F'"' '{print $4}'`

    cd $BASE_DIR
    # Replace IP and Authentication in node mapping file
    # ====================================
    cp -f $MAPPING_TPL $NODE_MAPPING
    sed -i "s/CA_NODE/${CA_NODE}/g" $NODE_MAPPING
    sed -i "s/ORG1_NODE/${ORG1_NODE}/g" $NODE_MAPPING
    sed -i "s/ORG2_NODE/${ORG2_NODE}/g" $NODE_MAPPING
    sed -i "s/ORG3_NODE/${ORG3_NODE}/g" $NODE_MAPPING
    sed -i "s/ORG4_NODE/${ORG4_NODE}/g" $NODE_MAPPING
    sed -i "s/SSH_USERNAME/${SSH_USERNAME}/g" $NODE_MAPPING
    sed -i "s/SSH_PASSWORD/${SSH_PASSWORD}/g" $NODE_MAPPING

    echo_stage "Deploy Fabric Network"
    cd $FABRIC_DEPLOYER
    python deploy_fabric.py -c configs/4org_kafka -m mappings/node_mapping.json

    # Copy all cryptos to /fabric_platform
    # ====================================
    cp -a configs/4org_kafka/crypto-config "$FABIRC_PLATFORM/configs"

    colorful_echo "Wait for Fabric Network to start, may take a while..." "yellow"
    sleep 60

    # Join peers into channel
    # ====================================
    cd $BASE_DIR
    HOSTS=`grep ORG $NODE_CONF | awk -F'=' '{print $2}'`
    for host in $HOSTS;do
        python utils/sshcopy.py $host $SSH_USERNAME $SSH_PASSWORD "utils/join.sh"
    done
    
    sleep 3
    
    python utils/sshexec.py $ORG1_NODE $SSH_USERNAME $SSH_PASSWORD 'bash /tmp/join.sh'
    sleep 10
    for host in $HOSTS;do
        colorful_echo "Join $host" "green"
        python utils/sshexec.py $host $SSH_USERNAME $SSH_PASSWORD 'bash /tmp/join.sh'
    done

}

function setup_explorer {
    EXPLORER="$BASE_DIR/explorer"
    EXPLORER_CONF_TPL="$EXPLORER/config/config.json.tpl"
    EXPLORER_CONF="$EXPLORER/config/config.json"
    EXPLORER_SQL="explorer/app/persistence/postgreSQL/db/*.sql"

    echo_stage "Deploy Explorer"

    cd $BASE_DIR
    cp -f $EXPLORER_CONF_TPL $EXPLORER_CONF
    sed -i "s/ORG1_NODE/${ORG1_NODE}/g" $EXPLORER_CONF
    sed -i "s/ORG2_NODE/${ORG2_NODE}/g" $EXPLORER_CONF
    sed -i "s/ORG3_NODE/${ORG3_NODE}/g" $EXPLORER_CONF
    sed -i "s/ORG4_NODE/${ORG4_NODE}/g" $EXPLORER_CONF

    cp $EXPLORER_SQL /tmp
    chmod o+rwx /tmp/*.sql
    sudo -u postgres psql -c '\i /tmp/explorerpg.sql'
    sudo -u postgres psql -c '\i /tmp/updatepg.sql'

    cd $EXPLORER
    bash "start.sh"
}

function setup_composer_playground {
    cd $BASE_DIR
    CARD_ORG="org1.example.com"
    CARD_NAME="PeerAdmin@hlfv1"
    PRIVATE_KEY_FILE=`ls -1 $FABIRC_PLATFORM/configs/crypto-config/peerOrganizations/$CARD_ORG/users/Admin@$CARD_ORG/msp/keystore`
    PRIVATE_KEY="$FABIRC_PLATFORM/configs/crypto-config/peerOrganizations/$CARD_ORG/users/Admin@$CARD_ORG/msp/keystore/$PRIVATE_KEY_FILE"
    CERT="$FABIRC_PLATFORM/configs/crypto-config/peerOrganizations/$CARD_ORG/users/Admin@$CARD_ORG/msp/signcerts/Admin@$CARD_ORG-cert.pem"

    echo_stage "Setup Composer Playground"

    rm -rf "/tmp/$CARD_NAME.card"
    # Generate connection.json
    # ====================================
    cat << EOF > /tmp/connection.json
{
    "name": "hlfv1",
    "x-type": "hlfv1",
    "x-commitTimeout": 300,
    "version": "1.0.0",
    "client": {
        "organization": "Org1",
        "connection": {
            "timeout": {
                "peer": {
                    "endorser": "300",
                    "eventHub": "300",
                    "eventReg": "300"
                },
                "orderer": "300"
            }
        }
    },
    "channels": {
        "composerchannel": {
            "orderers": [
                "orderer1.example.com"
            ],
            "peers": {
                "peer0.org1.example.com": {}
            }
        }
    },
    "organizations": {
        "Org1": {
            "mspid": "Org1MSP",
            "peers": [
                "peer0.org1.example.com"
            ],
            "certificateAuthorities": [
                "ca.org1.example.com"
            ]
        }
    },
    "orderers": {
        "orderer1.example.com": {
            "url": "grpc://${ORG1_NODE}:7050"
        }
    },
    "peers": {
        "peer0.org1.example.com": {
            "url": "grpc://${ORG1_NODE}:7051",
            "eventUrl": "grpc://${ORG1_NODE}:7053"
        }
    },
    "certificateAuthorities": {
        "ca.org1.example.com": {
            "url": "http://${CA_NODE}:7059",
            "caName": "ca.org1.example.com"
        }
    }
}
EOF
    composer card create -p /tmp/connection.json -u PeerAdmin -c "${CERT}" -k "${PRIVATE_KEY}" -r PeerAdmin -r ChannelAdmin --file "/tmp/$CARD_NAME.card"

    python utils/sshcopy.py $COMPOSER_NODE $SSH_USERNAME $SSH_PASSWORD "/tmp/$CARD_NAME.card"
    python utils/sshexec.py $COMPOSER_NODE $SSH_USERNAME $SSH_PASSWORD "composer card list"
    python utils/sshexec.py $COMPOSER_NODE $SSH_USERNAME $SSH_PASSWORD "composer card import --file /tmp/$CARD_NAME.card"
    python utils/sshexec.py $COMPOSER_NODE $SSH_USERNAME $SSH_PASSWORD "composer card list"

    # Start Composer Playground
    python utils/sshexec.py $COMPOSER_NODE $SSH_USERNAME $SSH_PASSWORD "nohup composer-playground &> /dev/null &" bg
}


function main {
    BASE_DIR=$( cd `dirname $0`; pwd -P)
    NODE_CONF="node-conf.sh"

    echo_banner
    # Print test warning
    colorful_echo "Tested on Ubuntu 16.04 Server and Desktop" "red"
    sleep 2

    # Import node configuration
    # ====================================
    . $NODE_CONF

    setup_fabric
    setup_explorer
    setup_composer_playground

    echo_banner_done
    colorful_echo "Hyperledger Fabric Explorer can be accessed through:" "yellow"
    colorful_echo "http://$CA_NODE:8081" "green"
    colorful_echo "Hyperledger Composer Playground:" "yellow"
    colorful_echo "http://$COMPOSER_NODE:8080" "green"
}

main

#!/usr/bin/env bash

# Stop on any error
set -e

FABRIC_DIR=${PWD}/..
export PATH=$FABRIC_DIR/bin:$PATH

CHANNEL=assgn3

# Chaincodes
CHAINCODE_DIRS=($FABRIC_DIR/assignment3/chaincode-javascript-snehal $FABRIC_DIR/assignment3/chaincode-go-tathagato $FABRIC_DIR/assignment3/chaincode-javascript-rutvij)
CHAINCODE_LANGS=(node golang node)


# Start network and create channels
./network.sh down
./network.sh up createChannel -c $CHANNEL

# Add third org
cd addOrg3
./addOrg3.sh up -c $CHANNEL
cd ..

ORG1=("Org1MSP" ${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt ${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp localhost:7051)
ORG2=("Org2MSP" ${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt ${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp localhost:9051)
ORG3=("Org3MSP" ${PWD}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt ${PWD}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp localhost:11051)

ORDERER_PEER_ADDRESS=localhost:7050
ORDERER_TLS_ROOT_CERT=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
ORGMSPS=(${ORG1[0]} ${ORG2[0]} ${ORG3[0]})
ORGCERTS=(${ORG1[1]} ${ORG2[1]} ${ORG3[1]})
ORGCONFIGS=(${ORG1[2]} ${ORG2[2]} ${ORG3[2]})
ORGADDS=(${ORG1[3]} ${ORG2[3]} ${ORG3[3]})

PACKAGENAME=auction

PACKAGEIDS=()
# Install the package on all endorser peers
for ((i=0; i<3; i++))
do
	# Package the chaincode
	cd ${CHAINCODE_DIRS[i]}
	if [ "${CHAINCODE_LANGS[i]}" = "node" ]
	then
		npm install
	else
		GO111MODULE=on go mod vendor
	fi
	cd -
	# To use peer CLI, add the peer binaries to path
	export PATH=${PWD}/../bin:$PATH
	export FABRIC_CFG_PATH=$PWD/../config/
	peer version
	peer lifecycle chaincode package auction.tar.gz --path ${CHAINCODE_DIRS[i]} --lang ${CHAINCODE_LANGS[i]} --label auction_1.0
	sleep 3
	echo "Chaincode packaging done"
	export CORE_PEER_TLS_ENABLED=true
	export CORE_PEER_LOCALMSPID=${ORGMSPS[i]}
	export CORE_PEER_TLS_ROOTCERT_FILE=${ORGCERTS[i]}
	export CORE_PEER_MSPCONFIGPATH=${ORGCONFIGS[i]}
	export CORE_PEER_ADDRESS=${ORGADDS[i]}
	peer lifecycle chaincode install auction.tar.gz
	sleep 3
	package_id=$(peer lifecycle chaincode queryinstalled)
	PACKAGEIDS[i]=`echo $package_id | tail -n 1 | cut -d',' -f1 | cut -d' ' -f3`
	echo "Chaincode queryinstalled"
done

# Once all peers installed now start approve
for ((i=0; i<3; i++))
do
	export CORE_PEER_TLS_ENABLED=true
	export CORE_PEER_LOCALMSPID=${ORGMSPS[i]}
	export CORE_PEER_TLS_ROOTCERT_FILE=${ORGCERTS[i]}
	export CORE_PEER_MSPCONFIGPATH=${ORGCONFIGS[i]}
	export CORE_PEER_ADDRESS=${ORGADDS[i]}
	export CC_PACKAGE_ID=${PACKAGEIDS[i]}
	echo $CC_PACKAGE_ID
	# Approve chaincode by the orderer
	peer lifecycle chaincode approveformyorg -o $ORDERER_PEER_ADDRESS --ordererTLSHostnameOverride orderer.example.com --channelID $CHANNEL --name $PACKAGENAME -v 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_TLS_ROOT_CERT
done

peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL --name $PACKAGENAME \
	--version 1.0 --sequence 1 --tls --cafile $ORDERER_TLS_ROOT_CERT --output json

# Commit chaincode
echo "Commiting chaincode"

peer lifecycle chaincode commit -o $ORDERER_PEER_ADDRESS --ordererTLSHostnameOverride orderer.example.com \
	--channelID $CHANNEL --name $PACKAGENAME --version 1.0 --sequence 1 --tls --cafile \
	$ORDERER_TLS_ROOT_CERT \
	--peerAddresses ${ORG1[3]} --tlsRootCertFiles ${ORG1[1]} \
	--peerAddresses ${ORG2[3]} --tlsRootCertFiles ${ORG2[1]} \
	--peerAddresses ${ORG3[3]} --tlsRootCertFiles ${ORG3[1]} 

echo "Check query commit"
for ((i=0; i<3; i++))
do
	export CORE_PEER_TLS_ENABLED=true
	export CORE_PEER_LOCALMSPID=${ORGMSPS[i]}
	export CORE_PEER_TLS_ROOTCERT_FILE=${ORGCERTS[i]}
	export CORE_PEER_MSPCONFIGPATH=${ORGCONFIGS[i]}
	export CORE_PEER_ADDRESS=${ORGADDS[i]}

	# Check if query committed on all orgs
	peer lifecycle chaincode querycommitted --channelID $CHANNEL --name $PACKAGENAME \
		--cafile $ORDERER_TLS_ROOT_CERT
done
peer chaincode list --installed
#create auction
echo "Creating the Auction"

export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG1[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG1[2]}
export CORE_PEER_ADDRESS=${ORG1[3]}
echo $CORE_PEER_MSPCONFIGPATH
peer chaincode invoke -o $ORDERER_PEER_ADDRESS --ordererTLSHostnameOverride orderer.example.com --tls --cafile \
	$ORDERER_TLS_ROOT_CERT -C $CHANNEL -n $PACKAGENAME \
	--peerAddresses ${ORG1[3]} --tlsRootCertFiles ${ORG1[1]} \
	--peerAddresses ${ORG2[3]} --tlsRootCertFiles ${ORG2[1]} \
	--peerAddresses ${ORG3[3]} --tlsRootCertFiles ${ORG3[1]} \
	-c '{"function":"createAuction","Args":["Asset1"]}'
sleep 3
echo "Auction updated"
peer chaincode query -C $CHANNEL -n $PACKAGENAME -c '{"Args":["getAuction", "Asset1"]}'


echo "Submit bid 1"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG1[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG1[2]}
export CORE_PEER_ADDRESS=${ORG1[3]}
echo $CORE_PEER_LOCALMSPID
peer chaincode invoke -o $ORDERER_PEER_ADDRESS --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_TLS_ROOT_CERT \
	-C $CHANNEL -n $PACKAGENAME \
	--peerAddresses ${ORG1[3]} --tlsRootCertFiles ${ORG1[1]} \
	--peerAddresses ${ORG2[3]} --tlsRootCertFiles ${ORG2[1]} \
	--peerAddresses ${ORG3[3]} --tlsRootCertFiles ${ORG3[1]} \
	-c '{"function":"submitBid","Args":["Asset1", "200"]}'
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG1[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG1[2]}
export CORE_PEER_ADDRESS=${ORG1[3]}
echo "Auction updated"
peer chaincode query -C $CHANNEL -n $PACKAGENAME -c '{"Args":["getAuction", "Asset1"]}'export CORE_PEER_TLS_ENABLED=true

echo "Submit bid 2"
export CORE_PEER_LOCALMSPID=${ORG2[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG2[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG2[2]}
export CORE_PEER_ADDRESS=${ORG2[3]}
echo $CORE_PEER_LOCALMSPID
peer chaincode invoke -o $ORDERER_PEER_ADDRESS --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_TLS_ROOT_CERT \
	-C $CHANNEL -n $PACKAGENAME \
	--peerAddresses ${ORG1[3]} --tlsRootCertFiles ${ORG1[1]} \
	--peerAddresses ${ORG2[3]} --tlsRootCertFiles ${ORG2[1]} \
	--peerAddresses ${ORG3[3]} --tlsRootCertFiles ${ORG3[1]} \
	-c '{"function":"submitBid","Args":["Asset1", "450"]}'
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG1[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG1[2]}
export CORE_PEER_ADDRESS=${ORG1[3]}
echo "Auction updated"
peer chaincode query -C $CHANNEL -n $PACKAGENAME -c '{"Args":["getAuction", "Asset1"]}'

echo "Submit bid 3"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG3[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG3[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG3[2]}
export CORE_PEER_ADDRESS=${ORG3[3]}
echo $CORE_PEER_LOCALMSPID
peer chaincode invoke -o $ORDERER_PEER_ADDRESS --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_TLS_ROOT_CERT \
	-C $CHANNEL -n $PACKAGENAME \
	--peerAddresses ${ORG1[3]} --tlsRootCertFiles ${ORG1[1]} \
	--peerAddresses ${ORG2[3]} --tlsRootCertFiles ${ORG2[1]} \
	--peerAddresses ${ORG3[3]} --tlsRootCertFiles ${ORG3[1]} \
	-c '{"function":"submitBid","Args":["Asset1", "300"]}'
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG1[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG1[2]}
export CORE_PEER_ADDRESS=${ORG1[3]}
echo "Auction updated"
peer chaincode query -C $CHANNEL -n $PACKAGENAME -c '{"Args":["getAuction", "Asset1"]}'

export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG3[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG3[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG3[2]}
export CORE_PEER_ADDRESS=${ORG3[3]}
peer chaincode invoke -o $ORDERER_PEER_ADDRESS --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_TLS_ROOT_CERT \
	-C $CHANNEL -n $PACKAGENAME \
	--peerAddresses ${ORG1[3]} --tlsRootCertFiles ${ORG1[1]} \
	--peerAddresses ${ORG2[3]} --tlsRootCertFiles ${ORG2[1]} \
	--peerAddresses ${ORG3[3]} --tlsRootCertFiles ${ORG3[1]} \
	-c '{"function":"declareWinner","Args":["Asset1"]}'

sleep 2

export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=${ORG1[0]}
export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1[1]}
export CORE_PEER_MSPCONFIGPATH=${ORG1[2]}
export CORE_PEER_ADDRESS=${ORG1[3]}
peer chaincode query -C $CHANNEL -n $PACKAGENAME -c '{"Args":["getAuction", "Asset1"]}'

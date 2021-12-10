/*
SPDX-License-Identifier: Apache-2.0
*/
/// @title go smart contract(chaincode) for first priced auction
/// @author Tathagato Roy 

package main

import (
	"encoding/json"
	"fmt"
    "log"
	"strconv"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type SmartContract struct {
	contractapi.Contract
}

/// @dev Structure of the Asset being bid on
/// @param ID id of the assett
/// @param Owner of the asset
/// @param Description describes the asset
type Asset struct {
    ID    int `json:"id"`
    Owner string `json:"owner"`
	Description string `json:"description"`
}
///@dev to describe the auction status
const (
    ACTIVE  = "ACTIVE"
    BIDOVER = "BIDOVER"
    FINISHED = "FINISHED"
)
/// @dev used to assign id to a asset
var next_id = 0

/// @dev Structure containing the AuctionAuction data
/// @param Asset describes the Asset
/// @param Bids stores all Bids (need not be blind)
/// @param Winner The chosen Winner
/// @param WinningPrice  Final Winning Price
/// @param Status : Finished or Active
type Auction struct {
	Asset        Asset              `json : "asset"` 
	Bids         map[string]int `json:"bids"`
	
	Winner       string             `json:"winner"`
	WinningPrice int                `json:"price"`
	Status       string             `json:"status"`
}
/// @notice  write auction to the ledger
/// @param auction  auction to create
/// @return Error if any
func (s *SmartContract) commitAuction(ctx contractapi.TransactionContextInterface, auction *Auction) error {
    auctionJSON, err := json.Marshal(auction)
    if err != nil {
        return fmt.Errorf("Failed to encode auction JSON: %v", err)
    }

    // Put write to ledger
    err = ctx.GetStub().PutState(strconv.Itoa(auction.Asset.ID), auctionJSON)
    if err != nil {
        return fmt.Errorf("Failed to put auction in public data: %v", err)
    }

    return nil
}

/// @notice Function to query state of a auction
/// @param assetID The assetID for the auction to get
/// @return auction state or error
func (s *SmartContract) getAuction(ctx contractapi.TransactionContextInterface, assetID int) (*Auction, error) {

    auctionJSON, err := ctx.GetStub().GetState(strconv.Itoa(assetID))
    if err != nil {
        return nil, fmt.Errorf("Unable to get auction state %v: %v", assetID, err)
    }
    if auctionJSON == nil {
        return nil, fmt.Errorf("Asset ID provided is wrong")
    }

    var auction *Auction
    err = json.Unmarshal(auctionJSON, &auction)
    if err != nil {
        return nil, err
    }

    return auction, nil
}

/// @notice Function to create an auction for an asset
/// @param assetDescription describes the asset 
/// @return Error if it fails to  get client
func (s *SmartContract) createAuction(ctx contractapi.TransactionContextInterface, assetDescription string) error {
    // Get the MSP ID of the org creating the auction
    orgID, err := ctx.GetClientIdentity().GetMSPID()
    if err != nil {
        return fmt.Errorf("Failed to get client MSP ID: %v", err)
    }

    bids := make(map[string]int)
    asset := Asset{
        ID:    next_id,
        Owner: orgID,
		Description : assetDescription,
    }

	/// create auction
    auction := Auction{
        Asset:        asset,
        Bids:         bids,
        Winner:       "",
        WinningPrice: -1000,
        Status:       ACTIVE,
    }
	next_id += 1
	/// commit to the ledger
    return s.commitAuction(ctx, &auction)
}
/// @notice Submit bid by peer
/// @param assetID ID of the asset on which bid is made
/// @param bid_value The bidding amount
/// @return Error if any
/// @dev The function rejects if a bid has already been made by an org
func (s *SmartContract) submitBid(ctx contractapi.TransactionContextInterface, assetID int, value int) error {
    // Get the MSP ID of the bidding org
    orgID, err := ctx.GetClientIdentity().GetMSPID()
    if err != nil {
        return fmt.Errorf("Failed to get client MSP ID: %v", err)
    }

    // Get auction
    auction, err := s.getAuction(ctx, assetID)
    if err != nil {
        return fmt.Errorf("Failed to get auction from ledger %v", err)
    }

    //  if auction is finished
    if auction.Status == FINISHED {
        return fmt.Errorf("Auction Finished")
    }

    //  if bid is positive
    if value <= 0 {
        return fmt.Errorf("Bid value has to be positive")
    }

    // Check if bid is already made
    if _, ok := auction.Bids[orgID]; ok {
        return fmt.Errorf("This Organisation has already made a bid")
    }

    auction.Bids[orgID] = value

    // Update the ledger
    return s.commitAuction(ctx, auction)
}

/// @notice calls to set the winner
/// @notice essentially ends the auction and declares the winner
/// @notice only allows the owner of the asset to call this 
/// @param assetID The assetID of auction to declare the winner of
/// @return Error if any
func (s *SmartContract) declareWinner(ctx contractapi.TransactionContextInterface, assetID int) error {
    // Get auction
    auction, err := s.getAuction(ctx, assetID)
    if err != nil {
        return fmt.Errorf("Failed to get auction from public state %v", err)
    }
	// Get the MSP ID of the org calling this function
    orgID, err := ctx.GetClientIdentity().GetMSPID()
    if err != nil {
        return fmt.Errorf("Failed to get client MSP ID: %v", err)
    }
	if orgID != auction.Asset.Owner{
		return fmt.Errorf("Only the owner of the asset can end the auction")
	}

    winningPrice := -1
    winner := ""
    for bidder, bidvalue := range auction.Bids {
        if bidvalue > winningPrice {
            winningPrice = bidvalue
            winner = bidder
        }
    }
    if len(winner) == 0 {
        return fmt.Errorf("No winner as no bid, Auction remains open for now")
    }


    auction.Winner = winner
    auction.Status = FINISHED
    auction.WinningPrice = winningPrice
    auction.Asset.Owner = winner

    // Update the state
    return s.commitAuction(ctx, auction)
}

func main() {
    auctionChaincode, err := contractapi.NewChaincode(&SmartContract{})
    if err != nil {
      log.Panicf("Error creating assignment3 chaincode: %v", err)
    }
  
    if err := auctionChaincode.Start(); err != nil {
      log.Panicf("Error starting assignment3 chaincode: %v", err)
    }
  }
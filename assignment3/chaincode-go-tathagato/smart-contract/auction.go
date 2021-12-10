/// @title Smart contract for first price auction
/// @Author Tathagato Roy

package auction

import (
    "encoding/json"
    "fmt"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

const (
    BIDDING  = "ACTIVE"
    FINISHED = "ENDED"
)

type SmartContract struct {
    contractapi.Contract
}

/// @dev Structure containing information about the asset on auction
/// @param ID The asset ID
/// @param Owner The owner of the asset
type Asset struct {
    ID    string `json:"ID"`
    Owner string `json:"owner"`
}

/// @dev Structure containing information about an auction instance
/// @param Auction The asset on auction
/// @param Bids The list of bids made on an auction
/// @param Winner The winner of the auction
/// @param WinningPrice The price for which the asset was sold
/// @param Status The status of the auction ("bidding"/"finished")
type Auction struct {
    Asset        Asset          `json:"asset"`
    Status       string         `json:"status"`
    Bids         map[string]int `json:"bids"`
    Winner       string         `json:"winner"`
    WinningPrice int            `json:"winningPrice"`
}

/// @notice Function to create an auction for an asset
/// @param assetID The assetID of the asset for which auction has been created
/// @return Error if any
func (s *SmartContract) createAuction(ctx contractapi.TransactionContextInterface, assetID string) error {
    // Get the MSP ID of the org creating the auction
    orgID, err := ctx.GetClientIdentity().GetMSPID()
    if err != nil {
        return fmt.Errorf("Failed to get client MSP ID: %v", err)
    }

    // Create auction
    bids := make(map[string]int)
    asset := Asset{
        ID:    assetID,
        Owner: orgID,
    }

    auction := Auction{
        Asset:        asset,
        Bids:         bids,
        Winner:       "",
        WinningPrice: -1,
        Status:       BIDDING,
    }

    return s.WriteAuction(ctx, assetID, &auction)
}

/// @notice Function to make a bid on behalf of an organisation
/// @param assetID The assetID of the asset on which bid has to be made
/// @param value The amount to bid
/// @return Error if any
/// @dev The function rejects if a bid has already been made by an org
func (s *SmartContract) submitBid(ctx contractapi.TransactionContextInterface, assetID string, value int) error {
    // Get the MSP ID of the bidding org
    orgID, err := ctx.GetClientIdentity().GetMSPID()
    if err != nil {
        return fmt.Errorf("Failed to get client MSP ID: %v", err)
    }

    // Get auction
    auction, err := s.getAuction(ctx, assetID)
    if err != nil {
        return fmt.Errorf("Failed to get auction from public state %v", err)
    }

    // Check if auction is finished
    if auction.Status == FINISHED {
        return fmt.Errorf("Can't bid on a finished auction")
    }

    // Check if bid is positive
    if value <= 0 {
        return fmt.Errorf("Bid value should be positive")
    }

    // Check if bid is already made
    if _, ok := auction.Bids[orgID]; ok {
        return fmt.Errorf("Already submitted a bid to the auction")
    }

    auction.Bids[orgID] = value

    // Update the state
    return s.WriteAuction(ctx, assetID, auction)
}

/// @notice Function called to set the winner
/// @param assetID The assetID of auction to declare the winner of
/// @return Error if any
func (s *SmartContract) declareWinner(ctx contractapi.TransactionContextInterface, assetID string) error {
    // Get auction
    auction, err := s.getAuction(ctx, assetID)
    if err != nil {
        return fmt.Errorf("Failed to get auction from public state %v", err)
    }

    max := -1
    winner := ""
    for bidder, value := range auction.Bids {
        if value > max {
            max = value
            winner = bidder
        }
    }
    if len(winner) == 0 {
        return fmt.Errorf("No one has bid yet, can't declare winner")
    }

    // Update auction
    auction.Winner = winner
    auction.Status = FINISHED
    auction.WinningPrice = max
    auction.Asset.Owner = winner

    // Update the state
    return s.WriteAuction(ctx, assetID, auction)
}

/// @notice Function to write auction to the global state
/// @param auction The auction to write
/// @return Error if any
func (s *SmartContract) WriteAuction(ctx contractapi.TransactionContextInterface, assetID string, auction *Auction) error {
    auctionJSON, err := json.Marshal(auction)
    if err != nil {
        return fmt.Errorf("Failed to encode auction JSON: %v", err)
    }

    // Put auction in state
    err = ctx.GetStub().PutState(assetID, auctionJSON)
    if err != nil {
        return fmt.Errorf("Failed to put auction in public data: %v", err)
    }

    return nil
}

/// @notice Function to get auction based upon assetID
/// @param assetID The assetID for the auction to get
func (s *SmartContract) getAuction(ctx contractapi.TransactionContextInterface, assetID string) (*Auction, error) {

    auctionJSON, err := ctx.GetStub().GetState(assetID)
    if err != nil {
        return nil, fmt.Errorf("Failed to get auction object %v: %v", assetID, err)
    }
    if auctionJSON == nil {
        return nil, fmt.Errorf("Auction does not exist")
    }

    var auction *Auction
    err = json.Unmarshal(auctionJSON, &auction)
    if err != nil {
        return nil, err
    }

    return auction, nil
}
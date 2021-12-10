"use strict";

const { Contract } = require("fabric-contract-api");
const { ClientIdentity } = require("fabric-shim");

/// @author Snehal Kumar
/// @notice Auction contract class
class Auction extends Contract {

  /// @param assetID the ID of the asset being auctioned
  async createAuction(ctx, assetID) {
    const cid = new ClientIdentity(ctx.stub);
    const orgID = cid.getMSPID();

    const auction = {
      asset: {
        ID: assetID,
        owner: orgID,
      },
      status: "ACTIVE",
      bids: {},
      winner: "",
      winningPrice: -1,
    };

    ctx.stub.putState(assetID, Buffer.from(JSON.stringify(auction)));
  }

  /// @notice Function to make a bid
  /// @param assetID the ID of the asset being auctioned
  /// @param bidAmount the amount bid by the peer
  /// @dev Checks for valid asset and bid amount included
  async submitBid(ctx, assetID, bidAmount) {
    const cid = new ClientIdentity(ctx.stub);
    const orgID = cid.getMSPID();

    let auct = await ctx.stub.getState(assetID);
    /// Check for valid asset
    if (!auct){
      throw new Error(`Auction with assetID doesn't exist`);
    } else if(auct.toString().length <= 0) {
      throw new Error(`Auction with assetID doesn't exist`);
    }

    
    let bid = parseInt(bidAmount);
    /// Check for valid bid
    if (bid <= 0) {
      throw new Error("Not a valid bid value");
    }
    
    let auction = JSON.parse(auct.toString());
    /// Check if auction has ended
    if (auction.status == "ENDED") {
      throw new Error("Auction ended");
    }

    /// Check if bid already made by peer
    if (orgID in auction.bids) {
      throw new Error("Bid already made");
    }
    auction.bids[orgID] = bid;
    console.log(`auctionstuff:`,auction);
    ctx.stub.putState(assetID, Buffer.from(JSON.stringify(auction)));
  }

  /// @notice Function to get the auction.
  /// @param assetID the ID of the asset being auctioned
  /// @returns The auction of corresponding asset ID.
  async getAuction(ctx, assetID) {
    const auct = await ctx.stub.getState(assetID);
    /// Check for valid auction
    if (!auct){
      throw new Error(`Auction with assetID doesn't exist`);
    } else if(auct.toString().length <= 0) {
      throw new Error(`Auction with assetID doesn't exist`);
    }
   
    let auction = JSON.parse(auct.toString());
    return auction;
  }

  /// @notice Function to evaluate and declare the winner of the asset
  /// @param assetID the ID of the asset being auctioned
  /// @dev Checks for valid asset and bids included
  async declareWinner(ctx, assetID) {
    let winningPrice = -1;
    let winner = null;
    const auct = await ctx.stub.getState(assetID);
    /// Check for valid asset
    if (!auct){
      throw new Error(`Auction with assetID doesn't exist`);
    } else if(auct.toString().length <= 0) {
      throw new Error(`Auction with assetID doesn't exist`);
    }

    let auction = JSON.parse(auct.toString());
    
    /// Check for no bids
    if (Object.keys(auction.bids).length === 0) {
      throw new Error("No bids made");
    }

    /// Calculate the highest bidder
    Object.keys(auction.bids).forEach((key) => {
      if (auction.bids[key] > winningPrice) {
        winningPrice = auction.bids[key];
        winner = key;
      }
    });

    auction.status = "ENDED";
    auction.winner = winner;
    auction.winningPrice = winningPrice;
    auction.asset.owner = winner;
    const auc = JSON.stringify(auction);
    ctx.stub.putState(assetID, Buffer.from(auc));
  }
}

module.exports = Auction;
"use strict";

/// @author Rutvij Menavlikar
/// @notice The auction contract implementation
const { Contract } = require("fabric-contract-api");
const { ClientIdentity } = require("fabric-shim");

/// @notice the status of the auction
const OPEN = "ACTIVE";

class Auction extends Contract {
  /// @param assetID the ID of the asset being auctioned
  async createAuction(ctx, assetID) {
    const orgID = await this.getClient(ctx);
    const auction = {
      asset: {
        ID: assetID,
        owner: orgID,
      },
      status: OPEN,
      bids: {},
      winner: "",
      winningPrice: -1,
    };

    ctx.stub.putState(assetID, Buffer.from(JSON.stringify(auction)));
  }

  /// @notice Function to submit bid
  /// @param assetID the ID of the asset being auctioned
  /// @param amount amount of bid
  async submitBid(ctx, assetID, amount) {
    
    const bidval = parseInt(amount);
    /// Check for valid bid amount
    if (bidval <= 0) {
      throw new Error("Invalid bid value");
    }
    
    let auction = await this.getAuction(ctx, assetID);
    const orgID = await this.getClient(ctx);
    
    /// Check for already placed bid 
    if (orgID in auction.bids) {
      throw new Error("Bid already placed");
    }

    /// Check for active auction
    if (auction.status != OPEN) {
      throw new Error("Auction is over");
    }

    // Setting the bid value according the orgId.
    auction.bids[orgID] = bidval;

    ctx.stub.putState(assetID, Buffer.from(JSON.stringify(auction)));
  }

  /// @notice Function to declare the winner of auction
  /// @param assetID the ID of the asset being auctioned
  async declareWinner(ctx, assetID) {
    const auction = await this.getAuction(ctx, assetID);
    let newwinner = "";
    let finalbid = -1;
    for (let key in auction.bids) {
      if (auction.bids[key] > finalbid) {
        newwinner = key;
        finalbid = auction.bids[key];
      }
    }
    /// Check for no bids
    if (newwinner === "") {
      throw new Error("No one has made any bids");
    }

    // Setting the auction status to finished.
    auction.asset.owner = newwinner;
    auction.winner = newwinner;
    auction.winningPrice = finalbid;
    auction.status = "ENDED";

    ctx.stub.putState(assetID, Buffer.from(JSON.stringify(auction)));
  }

  /// @notice Function to get the auction.
  /// @param assetID the ID of the asset being auctioned
  /// @returns The auction of corresponding asset ID.
  async getAuction(ctx, assetID) {
    const auctionBytes = await ctx.stub.getState(assetID);
    /// Check for valid auction
    if (!auctionBytes || auctionBytes.toString().length <= 0) {
      throw new Error(`Auction does not exist`);
    }

    const auction = JSON.parse(auctionBytes.toString());
    return auction;
  }

  /// @notice Function to get the client
  /// @returns The client
  async getClient(ctx) {
    const cid = new ClientIdentity(ctx.stub);
    return cid.getMSPID();
  }
}

module.exports = Auction;
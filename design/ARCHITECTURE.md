# Moonraker Architecture

## Contracts

```mermaid
classDiagram
  direction LR
  FeeManager --|> Router

  Owned --|> WithModules
  class Owned {
    <<Abstract>>
    +address owner
    ~onlyOwner()
    +transferOwnership(address newOwner,onlyOwner)
  }

  WithModules --|> Auctioneer
  class WithModules {
    <<Abstract>>
    +List~WithModules.Keycode~ modules
  }

  class Auctioneer {
    <<Abstract>>
    struct Routing
    struct RoutingParams
    +uint256 lotCounter
    +mapping[Keycode auctionType -> bool] typeSunset
    +mapping[uint256 lotId -> Routing] lotRouting
    +createAuction(RoutingParams routing, Auction.AuctionParams params) uint256
    +closeAuction(uint256 lotId)
    +getRouting(uint256 lotId) Routing
    +payoutFor(uint256 lotId) Routing
    +priceFor(uint256 lotId, uint256 amount) uint256
    +maxPayout(uint256 lotId) uint256
    +maxAmountAccepted(uint256 lotId) uint256
    +isLive(uint256 lotId) bool
    +ownerOf(uint256 lotId) address
    +remainingCapacity(lotId) uint256
  }

  class FeeManager {
    <<Abstract>>
    +uint48 protocolFee
    +uint48 constant FEE_DECIMALS = 1e5
    +mapping[address referrer -> uint48] referrerFees
    +mapping[address -> mapping[ERC20 -> uint256]] rewards
    +claimFees(): uint256
  }

  class Router {
    <<Abstract>>
    ~address immutable treasury
    +purchase(address recipient, address referrer, uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData, bytes approval): uint256
    +bid(address recipient, address referrer, uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData, bytes approval)
    +settle(uint256 lotId): uint256[]
    +settle(uint256 lotId, Auction.Bid[] bids): uint256[]
  }

  class Derivatizer {
    <<Abstract>>
    +transform(Keycode fromType, bytes calldata fromData, Keycode toType, bytes calldata toData, uint256 amount)
    +transform(Keycode fromType, uint256 fromTokenId, Keycode toType, bytes calldata toData, uint256 amount)
    +transform(Keycode fromType, uint256 fromTokenId, Keycode toType, uint256 toTokenId, uint256 amount)
  }

  class AuctionHouse {
    +purchase(address recipient, address referrer, uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData, bytes approval): uint256
    ~handleTransfers(Routing routing, uint256 amount, uint256 payout, uint256 feePaid, bytes approval)
    ~handlePayouts(uint256 lotId, Routing routing, address recipient, uint256 payout, bytes auctionOutput)
    +bid(address recipient, address referrer, uint256 lotId, uint256 amount, uint256 minAmountOut, bytes32 auctionData, bytes approval)
    +settle(uint256 lotId): uint256[]
    +settle(uint256 lotId, Auction.Bid[] bids): uint256[]
  }

  class Condenser {
    <<Abstract>>
    +condense(bytes auctionOutput, bytes derivativeConfig): bytes combined
  }

  class Module {
    <<Abstract>>
    +address parent
    ~onlyParent()
    +KEYCODE(): Keycode
    #INIT()
  }

  class WithModules {
    <<Abstract>>
    +Keycode[] modules
    +mapping[Keycode => Module] getModuleForKeycode
    +mapping[Keycode => bool] moduleSunset
    #installModule(Module module)
    #sunsetModule(Keycode keycode)
    #execOnModule(Keycode keycode, bytes callData): bytes
    +getModules(): Keycode[]
    ~moduleIsInstalled(Keycode keycode): bool
    ~getModuleIfInstalled(Keycode keycode): Module
    ~validateModule(Module module): Keycode
  }

  AuctionModule ..> Auctioneer

  DerivativeModule ..> Derivatizer
  
  CondenserModule ..> AuctionHouse
  Auctioneer --|> AuctionHouse
  Derivatizer --|> AuctionHouse
  Router --|> AuctionHouse

  WithModules --|> Derivatizer

  Condenser --|> CondenserModule
  Module --|> CondenserModule

  Auction --|> AuctionModule
  Module --|> AuctionModule

  class Auction {
    <<interface>>
    struct Lot
    struct Bid
    struct AuctionParams
    +bool allowNewMarkets
    +uint48 minAuctionDuration
    ~uint48 ONE_HUNDRED_PERCENT = 1e5
    +mapping[uint256 lotId => Lot] lotData
    +purchase(uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData) (uint256, bytes)
    +bid(uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData) (uint256, bytes)
    +settle(uint256 lotId) uint256[]
    +settle(uint256 lotId, Bid[] bids) uint256[]
    +createAuction(uint256 lotId, AuctionParams params)
    +closeAuction(uint256 lotId)
    +getRouting(uint256 lotId) Routing
    +payoutFor(uint256 lotId, uint256 amount) uint256
    +maxPayout(uint256 lotId) uint256
    +maxAmountAccepted(uint256 lotId) uint256
    +isLive(uint256 lotId) bool
    +ownerOf(uint256 lotId) address
    +remainingCapacity(uint256 lotId) uint256
  }

  class AuctionModule {
    <<abstract>>
    +purchase(uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData) (uint256, bytes)
    +bid(uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData) (uint256, bytes)
    +settle(uint256 lotId) uint256[]
    +settle(uint256 lotId, Bid[] bids) uint256[]
    +createAuction(uint256 lotId, AuctionParams params)
    +closeAuction(uint256 lotId)
    +getRouting(uint256 lotId) Routing
    +isLive(uint256 lotId) bool
    +ownerOf(uint256 lotId) address
    +remainingCapacity(uint256 lotId) uint256
  }

  Module --|> DerivativeModule
  Derivative --|> DerivativeModule
  ERC6909 --|> DerivativeModule

  class Derivative {
    <<abstract>>
    struct Token
    +mapping[Keycode dType => address] wrappedImplementations
    +mapping[uint256 tokenId => Token] tokenMetadata
    +mapping[uint256 lotId => uint256[]] lotDerivatives
    +deploy(bytes data, bool wrap) (uint256, address)
    +mint(bytes data, uint256 amount, bool wrapped) bytes
    +mint(uint256 tokenId, uint256 amount, bool wrapped) bytes
    +redeem(uint256 tokenId, uint256 amount, bool wrapped)
    +exercise(uint256 tokenId, uint256 amount, bool wrapped)
    +reclaim(uint256 tokenId)
    +wrap(uint256 tokenId, uint256 amount)
    +unwrap(uint256 tokenId, uint256 amount)
    #transform(uint256 tokenId, uint256 amount, bool wrapped)
    +exerciseCost(uint256 tokenId, uint256 amount) uint256
    +convertsTo(uint256 tokenId, uint256 amount) uint256
    +computeTokenId(bytes data) uint256
  }

  class ERC6909 {
    <<abstract>>
    +mapping[uint256 => uint256] totalSupply
    +mapping[address => mapping[address => bool]] isOperator
    +mapping[address => mapping[uint256 => uint256]] balanceOf
    +mapping[address => mapping[address => mapping[uint256 => uint256]]] allowance
    +transfer(address receiver, uint256 id, uint256 amount) bool
    +transferFrom(address sender, address receiver, uint256 id, uint256 amount) bool
    +approve(address spender, uint256 id, uint256 amount) bool
    +setOperator(address operator, bool approved) bool
    +supportsInterface(bytes4 interfaceId) bool
  }

  Module ..> WithModules

  AuctionModule --|> GDA
  AuctionModule --|> 2DGDA
  
  DerivativeModule --|> CliffVesting
  DerivativeModule --|> StakedCliffVesting
  DerivativeModule --|> RageVesting
  DerivativeModule --|> FixedStrikeOption
  DerivativeModule --|> SuccessToken

  
```

### TODOs
- [ ] Add section for Auction and Derivative module implementations after we prioritize which ones to build first
- [ ] Create a function or add return values so that a solver / user can determine the derivative token that a market will return (useful for then creating off-chain orders for that token). This also brings up a point about how certain auction view functions that rely solely on an amount need to be refactored for a multi-variate auction world, e.g. `payoutFor(uint256)` -> `payoutFor(uint256, bytes)`


## Processes

### Create an Auction

```mermaid
sequenceDiagram
  autoNumber
  participant AuctionOwner
  participant AuctionHouse
  participant AtomicAuctionModule

  AuctionOwner->>AuctionHouse: Auctioneer.createAuction(RoutingParams routing, Auction.AuctionParams params)
  activate AuctionHouse
    AuctionHouse->>AuctionHouse: _getModuleIfInstalled(auctionType)

    AuctionHouse->>AtomicAuctionModule: createAuction(uint256 id, Auction.AuctionParams params)
    activate AtomicAuctionModule
      Note right of AtomicAuctionModule: validation, creates Lot record
      AtomicAuctionModule->>AtomicAuctionModule: _createAuction(uint256 id, Lot lot, bytes implParams)
      Note right of AtomicAuctionModule: module-specific actions

      AtomicAuctionModule-->>AuctionHouse: 
    deactivate AtomicAuctionModule

    Note over AuctionHouse: store routing information
  deactivate AuctionHouse

  AuctionHouse-->>AuctionOwner: auction id
```

### Purchase from an Atomic Auction (without hooks)

#### No Derivative

```mermaid
sequenceDiagram
  autoNumber
  participant Buyer
  participant AuctionHouse
  
  activate AuctionHouse
    Buyer->>AuctionHouse: purchase(address recipient, address referrer, uint256 auctionId, uint256 amount, uint256 minAmountOut, bytes approval)
    AuctionHouse->>AuctionHouse: _getModuleForId(uint256 auctionId)

    Note over AuctionHouse: purchase

    create participant AtomicAuctionModule
    AuctionHouse->>AtomicAuctionModule: purchase(uint256 auctionId, uint256 amount, uint256 minAmountOut)
    destroy AtomicAuctionModule
    AtomicAuctionModule-->>AuctionHouse: uint256 payoutAmount, bytes auctionOutput

    Note over AuctionHouse: transfers

    activate AuctionHouse
      AuctionHouse->>AuctionHouse: _handleTransfers(Routing routing, uint256 amount, address recipient, uint256 payout, bytes auctionOutput)
      create participant QuoteToken
      alt approval data is set
        AuctionHouse->>QuoteToken: permit(approval)
      end
      AuctionHouse->>QuoteToken: safeTransferFrom(buyer, auctionHouse, amount)
      Buyer-->>AuctionHouse: quote tokens transferred to AuctionHouse

      create participant PayoutToken
      AuctionHouse->>PayoutToken: safeTransferFrom(auctionOwner, auctionHouse, payoutAmount)
      AuctionOwner-->>AuctionHouse: payout tokens transferred to AuctionHouse

      destroy QuoteToken
      AuctionHouse->>QuoteToken: safeTransfer(auctionOwner, amountLessFee)
      AuctionHouse-->>AuctionOwner: quote tokens transferred to AuctionOwner
    deactivate AuctionHouse

    Note over AuctionHouse: payout

    AuctionHouse->>AuctionHouse: _handlePayout(uint256 id, Routing routing, address recipient, uint256 payout, bytes auctionOutput)
    destroy PayoutToken
    AuctionHouse->>PayoutToken: safeTransfer(recipient, payoutAmount)
    AuctionHouse-->>Buyer: transfer payout tokens

    AuctionHouse-->>Buyer: payout amount and encoded module + tokenId or wrapped token address
  deactivate AuctionHouse
```

#### With Derivative

```mermaid
sequenceDiagram
  autoNumber
  participant Buyer
  participant AuctionHouse

  activate AuctionHouse
    Buyer->>AuctionHouse: purchase(address recipient, address referrer, uint256 auctionId, uint256 amount, uint256 minAmountOut, bytes approval)
    AuctionHouse->>AuctionHouse: _getModuleForId(uint256 auctionId)

    Note over AuctionHouse: purchase

    create participant AtomicAuctionModule
    AuctionHouse->>AtomicAuctionModule: purchase(uint256 auctionId, uint256 amount, uint256 minAmountOut)
    destroy AtomicAuctionModule
    AtomicAuctionModule-->>AuctionHouse: uint256 payoutAmount, bytes auctionOutput

    Note over AuctionHouse: transfers

    activate AuctionHouse
      AuctionHouse->>AuctionHouse: _handleTransfers(Routing routing, uint256 amount, address recipient, uint256 payout, bytes auctionOutput)

      activate AuctionHouse
        create participant QuoteToken
        alt approval data is set
          AuctionHouse->>QuoteToken: permit(approval)
        end
        AuctionHouse->>QuoteToken: safeTransferFrom(buyer, auctionHouse, amount)
        Buyer-->>AuctionHouse: quote tokens transferred to AuctionHouse
      deactivate AuctionHouse

      activate AuctionHouse
        create participant PayoutToken
        AuctionHouse->>PayoutToken: safeTransferFrom(auctionOwner, auctionHouse, payoutAmount)
        AuctionOwner-->>AuctionHouse: payout tokens transferred to AuctionHouse
      deactivate AuctionHouse

      activate AuctionHouse
        destroy QuoteToken
        AuctionHouse->>QuoteToken: safeTransfer(auctionOwner, amountLessFee)
        AuctionHouse-->>AuctionOwner: quote tokens transferred to AuctionOwner
      deactivate AuctionHouse
    deactivate AuctionHouse

    Note over AuctionHouse: derivative payout

    activate AuctionHouse
      AuctionHouse->>AuctionHouse: _handlePayout(uint256 id, Routing routing, address recipient, uint256 payout, bytes auctionOutput)

      AuctionHouse->>AuctionHouse: _getModuleIfInstalled(derivativeType)

      alt condenserType is set
        AuctionHouse->>AuctionHouse: _getModuleIfInstalled(condenserType)

        create participant CondenserModule
        AuctionHouse->>CondenserModule: condense(auctionOutput, derivativeParams)
        destroy CondenserModule
        CondenserModule-->>AuctionHouse: derivative params overwritten
      end

      create participant DerivativeModule
      AuctionHouse->>DerivativeModule: mint(recipient, payout, derivativeParams, wrapDerivative)

      create participant DerivativeToken
      DerivativeModule->>DerivativeToken: safeTransfer(buyer, payout)

      destroy DerivativeToken
      DerivativeToken-->>Buyer: transfer derivative tokens
    deactivate AuctionHouse

    AuctionHouse-->>Buyer: payout amount
  deactivate AuctionHouse
```

### Close Atomic Auction

```mermaid
sequenceDiagram
  autoNumber
  participant AuctionOwner
  participant AuctionHouse
  participant AtomicAuctionModule

  activate AuctionHouse
    AuctionOwner->>AuctionHouse: close(uint256 id)
    
    AuctionHouse->>AuctionHouse: _getModuleForId(id)

    AuctionHouse->>AuctionHouse: lotRouting(id)

    alt isOwner == false
      AuctionHouse->>AuctionOwner: revert
    else
      AuctionHouse->>AtomicAuctionModule: close(id, auctionOwner)
      AuctionHouse-->>AuctionOwner: returns
    else
      AuctionHouse->>AuctionOwner: revert
    end    
  deactivate AuctionHouse
```

### Bid on an Auction

```mermaid
sequenceDiagram
  autoNumber
  participant Buyer
  participant AuctionHouse
  participant SDAAuctionModule

  activate AuctionHouse
    Buyer->>AuctionHouse: bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_)
    AuctionHouse->>AuctionHouse: _getModuleForId(uint256 auctionId)

    Note over SDAAuctionModule: TODO where are the bids stored?
    activate SDAAuctionModule
      AuctionHouse->>SDAAuctionModule: bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_)
      SDAAuctionModule->>SDAAuctionModule: records bid
      SDAAuctionModule-->>AuctionHouse: uint256 payoutAmount, bytes auctionOutput
    deactivate SDAAuctionModule

    activate AuctionHouse
      AuctionHouse->>AuctionHouse: _handleTransfers(Routing routing, uint256 amount, address recipient, uint256 payout, bytes auctionOutput)
      create participant QuoteToken
      AuctionHouse->>QuoteToken: safeTransferFrom(buyer, auctionHouse, amount)
      Buyer-->>AuctionHouse: quote tokens transferred to AuctionHouse
    deactivate AuctionHouse
  deactivate AuctionHouse
```

TODO transfer to AuctionHouse or the module?
TODO how buyer can claim quote tokens if the bid is unsuccessful?

### Settle an Auction

```mermaid
sequenceDiagram
  autoNumber
  participant AuctionOwner
  participant AuctionHouse
  participant SDAAuctionModule

  activate AuctionHouse
    AuctionOwner->>AuctionHouse: settle(uint256 auctionId)
    AuctionHouse->>AuctionHouse: _getModuleForId(uint256 auctionId)

    Note over SDAAuctionModule: TODO where are the bids stored?

    activate SDAAuctionModule
      AuctionHouse->>SDAAuctionModule: settle(auctionId, bids)

      Note over SDAAuctionModule: module-specific logic to determine payout
      SDAAuctionModule->>SDAAuctionModule: _settle(auctionId, bids)

      Note over SDAAuctionModule: TODO also needs bidId to retrieve recipient address?

      SDAAuctionModule-->>AuctionHouse: array of amounts
    deactivate SDAAuctionModule
    
  deactivate AuctionHouse
```

TODO when to transfer quote tokens to auction owner?
TODO when to transfer payout tokens from auction owner to auction house and then to buyer?

### User Redeems Derivative Token - V1 (through AuctionHouse, requires refactoring AuctionModule)

```mermaid
sequenceDiagram
  autoNumber
  participant User
  participant AuctionHouse
  participant DerivativeModule
  participant PayoutToken

  activate AuctionHouse
    User->>AuctionHouse: redeem(Keycode dType, uint256 tokenId, uint256 amount)

    AuctionHouse->>AuctionHouse: getModuleIfInstalled(dType)

    activate DerivativeModule
      AuctionHouse->>DerivativeModule: redeem(tokenId, amount)

      alt derivative token is wrapped
        create participant DerivativeToken
        DerivativeModule->>DerivativeToken: burn(user, amount)
        destroy DerivativeToken
        User-->>DerivativeToken: derivative tokens burned
      else 
        DerivativeModule->>DerivativeModule: burn(tokenId, user, amount)
        User-->>DerivativeModule: derivative tokens burned
      end
      DerivativeModule->>PayoutToken: safeTransfer(user, amount)
      DerivativeModule-->>User: payout tokens transferred
    deactivate DerivativeModule
  deactivate AuctionHouse
```

### User Redeems Derivative Token - V2 (direct with module)

```mermaid
sequenceDiagram
  autoNumber
  participant User
  participant DerivativeModule
  participant PayoutToken

  activate DerivativeModule
    User->>DerivativeModule: redeem(uint256 tokenId, uint256 amount)
    alt derivative token is wrapped
      create participant DerivativeToken
      DerivativeModule->>DerivativeToken: burn(user, amount)
      destroy DerivativeToken
      User-->>DerivativeToken: derivative tokens burned
    else 
      DerivativeModule->>DerivativeModule: burn(tokenId, user, amount)
      User-->>DerivativeModule: derivative tokens burned
    end
    DerivativeModule->>PayoutToken: safeTransfer(user, amount)
    DerivativeModule-->>User: payout tokens transferred
  deactivate DerivativeModule
```

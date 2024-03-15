# Axis Architecture

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
    +auction(RoutingParams routing, Auction.AuctionParams params) uint256
    +cancel(uint256 lotId)
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
    +batchPurchase(address recipient, address referrer, uint256[] lotIds, uint256[] amounts, uint256[] minAmountsOut, bytes[] auctionData, bytes[] approval): uint256[]
    +routePurchase(address recipient, address referrer, uint256[] lotIds, uint256 amount, uint256 minAmountOut, bytes[] auctionData, bytes approval): uint256
    +bid(address recipient, address referrer, uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData, bytes approval)
    +settle(uint256 lotId)
  }

  class Derivatizer {
    <<Abstract>>
    +transform(Keycode fromType, bytes calldata fromData, Keycode toType, bytes calldata toData, uint256 amount)
    +transform(Keycode fromType, uint256 fromTokenId, Keycode toType, bytes calldata toData, uint256 amount)
    +transform(Keycode fromType, uint256 fromTokenId, Keycode toType, uint256 toTokenId, uint256 amount)
  }

  class AuctionHouse {
    +purchase(address recipient, address referrer, uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData, bytes approval): uint256
    +batchPurchase(address recipient, address referrer, uint256[] lotIds, uint256[] amounts, uint256[] minAmountsOut, bytes[] auctionData, bytes[] approval): uint256[]
    +routePurchase(address recipient, address referrer, uint256[] lotIds, uint256 amount, uint256 minAmountOut, bytes[] auctionData, bytes approval): uint256
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
    ~uint48 _ONE_HUNDRED_PERCENT = 1e5
    +mapping[uint256 lotId => Lot] lotData
    +purchase(uint256 lotId, uint256 amount, bytes auctionData) (uint256, bytes)
    +bid(uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData) (uint256, bytes)
    +settle(uint256 lotId) uint256[]
    +settle(uint256 lotId, Bid[] bids) uint256[]
    +auction(uint256 lotId, address owner, AuctionParams params)
    +cancel(uint256 lotId)
    +payoutFor(uint256 lotId, uint256 amount) uint256
    +maxPayout(uint256 lotId) uint256
    +maxAmountAccepted(uint256 lotId) uint256
    +isLive(uint256 lotId) bool
    +ownerOf(uint256 lotId) address
    +remainingCapacity(uint256 lotId) uint256
  }

  class AuctionModule {
    <<abstract>>
    +purchase(uint256 lotId, uint256 amount, bytes auctionData) (uint256, bytes)
    +bid(uint256 lotId, uint256 amount, uint256 minAmountOut, bytes auctionData) (uint256, bytes)
    +settle(uint256 lotId) uint256[]
    +settle(uint256 lotId, Bid[] bids) uint256[]
    +auction(uint256 lotId, address owner, AuctionParams params)
    +cancel(uint256 lotId)
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
    +mapping[uint256 tokenId => Token] tokenMetadata
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
  AuctionModule --|> TVGDA

  DerivativeModule --|> CliffVesting
  DerivativeModule --|> StakedCliffVesting
  DerivativeModule --|> RageVesting
  DerivativeModule --|> FixedStrikeOption
  DerivativeModule --|> SuccessToken


```

### TODOs

-   [ ] Add section for Auction and Derivative module implementations after we prioritize which ones to build first
-   [ ] Create a function or add return values so that a solver / user can determine the derivative token that a market will return (useful for then creating off-chain orders for that token). This also brings up a point about how certain auction view functions that rely solely on an amount need to be refactored for a multi-variate auction world, e.g. `payoutFor(uint256)` -> `payoutFor(uint256, bytes)`

## Processes

### Create an Auction

```mermaid
sequenceDiagram
  autoNumber
  participant AuctionOwner
  participant AuctionHouse
  participant AtomicAuctionModule

  AuctionOwner->>AuctionHouse: Auctioneer.auction(RoutingParams routing, Auction.AuctionParams params)
  activate AuctionHouse
    AuctionHouse->>AuctionHouse: _getModuleIfInstalled(auctionType)

    AuctionHouse->>AtomicAuctionModule: auction(uint256 id, Auction.AuctionParams params)
    activate AtomicAuctionModule
      Note right of AtomicAuctionModule: validation, creates Lot record
      AtomicAuctionModule->>AtomicAuctionModule: _auction(uint256 id, Lot lot, bytes implParams)
      Note right of AtomicAuctionModule: module-specific actions

      AtomicAuctionModule-->>AuctionHouse:
    deactivate AtomicAuctionModule

    Note over AuctionHouse: store routing information
  deactivate AuctionHouse

  AuctionHouse-->>AuctionOwner: auction id
```

### Purchase from an Atomic Auction (without callbacks)

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

### Batch Auction: Buyer bids on an on-chain batch auction

```mermaid
sequenceDiagram
  autoNumber
  participant Buyer
  participant AuctionHouse
  participant BatchAuctionModule

  activate AuctionHouse
    Buyer->>AuctionHouse: bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_)
    AuctionHouse->>AuctionHouse: _getModuleForId(uint256 auctionId)

    activate BatchAuctionModule
      AuctionHouse->>BatchAuctionModule: bid(address recipient_, address referrer_, uint256 id_, uint256 amount_, uint256 minAmountOut_, bytes calldata auctionData_, bytes calldata approval_)
      SDAAuctionModule->>BatchAuctionModule: records bid
    deactivate BatchAuctionModule

  deactivate AuctionHouse
```

### Batch Auction: Auction is settled from bids stored on-chain

```mermaid
sequenceDiagram
  autoNumber
  participant AuctionOwner
  participant AuctionHouse
  participant BatchAuctionModule
  participant DerivativeModule
  participant Buyer(s)

  activate AuctionHouse
    AuctionOwner->>AuctionHouse: settle(uint256 auctionId)
    AuctionHouse->>AuctionHouse: _getModuleForId(uint256 auctionId)

    activate BatchAuctionModule
      AuctionHouse->>BatchAuctionModule: settle(auctionId)

      Note over BatchAuctionModule: module-specific logic to determine winning bids from stored bids
      BatchAuctionModule->>BatchAuctionModule: _settle(auctionId): Settlement settlement, bytes auctionOutput

      BatchAuctionModule-->>AuctionHouse: array of winningBids
    deactivate BatchAuctionModule

    AuctionOwner-->>AuctionHouse: base tokens transferred to AuctionHouse
    activate AuctionHouse
      Note over AuctionHouse: for each winning bid
      AuctionHouse->>AuctionHouse: _handleTransfers(Routing routing, uint256 amount, address recipient, uint256 payout)
      Buyer(s)-->>AuctionHouse: quote tokens transferred to AuctionHouse
      AuctionHouse->>AuctionHouse: _handlePayout(uint256 id, Routing routing, address recipient, uint256 payout, bytes auctionOutput)
      AuctionHouse-->>DerivativeModule: base tokens transferred to Derivative Module
      DerivativeModule-->>Buyer(s): payout tokens transferred to Buyer(s)
    deactivate AuctionHouse
    AuctionHouse-->>AuctionOwner: quote tokens transferred to AuctionOwner

  deactivate AuctionHouse
```

### User Redeems Derivative Token

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
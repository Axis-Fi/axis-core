// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

abstract contract ERC6909Metadata {
    /// @notice     Returns the name of the token
    ///
    /// @param      tokenId_    The ID of the token
    /// @return     string      The name of the token
    function name(
        uint256 tokenId_
    ) public view virtual returns (string memory);

    /// @notice     Returns the symbol of the token
    ///
    /// @param      tokenId_    The ID of the token
    /// @return     string      The symbol of the token
    function symbol(
        uint256 tokenId_
    ) public view virtual returns (string memory);

    /// @notice     Returns the number of decimals used by the token
    ///
    /// @param      tokenId_    The ID of the token
    /// @return     uint8       The number of decimals used by the token
    function decimals(
        uint256 tokenId_
    ) public view virtual returns (uint8);

    /// @notice     Returns the URI of the token
    ///
    /// @param      tokenId_    The ID of the token
    /// @return     string      The URI of the token
    function tokenURI(
        uint256 tokenId_
    ) public view virtual returns (string memory);

    /// @notice     Returns the total supply of the token
    ///
    /// @param      tokenId_    The ID of the token
    /// @return     uint256     The total supply of the token
    function totalSupply(
        uint256 tokenId_
    ) public view virtual returns (uint256);
}

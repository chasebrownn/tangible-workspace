// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/IOwnable.sol";

abstract contract Ownable is IOwnable {
    address internal _contractOwner;
    address internal _newContractOwner;

    constructor() {
        _contractOwner = msg.sender;
        emit OwnershipPushed(address(0), _contractOwner);
    }

    function contractOwner() public view override returns (address) {
        return _contractOwner;
    }

    modifier onlyOwner() {
        require(
            _contractOwner == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }

    function renounceOwnership() public virtual override onlyOwner {
        emit OwnershipPushed(_contractOwner, address(0));
        _contractOwner = address(0);
    }

    function pushOwnership(address newOwner_)
        public
        virtual
        override
        onlyOwner
    {
        require(
            newOwner_ != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipPushed(_contractOwner, newOwner_);
        _newContractOwner = newOwner_;
    }

    function pullOwnership() public virtual override {
        require(
            msg.sender == _newContractOwner,
            "Ownable: must be new owner to pull"
        );
        emit OwnershipPulled(_contractOwner, _newContractOwner);
        _contractOwner = _newContractOwner;
    }
}

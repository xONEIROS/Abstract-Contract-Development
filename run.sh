#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

print_color() {
    printf "${1}${2}${NC}\n"
}
print_header() {
    print_color $BLUE "
   ___                       _               
  / _ \                     (_)              
 | | | |_  _____  _ __   ___ _ _ __ ___  ___ 
 | | | \ \/ / _ \| '_ \ / _ \ | '__/ _ \/ __|
 | |_| |>  < (_) | | | |  __/ | | | (_) \__ \\
  \___//_/\_\___/|_| |_|\___|_|_|  \___/|___/
                                             
                                             "
    print_color $YELLOW "Welcome to the Hardhat Setup Script for Abstract | 0xOneiros"
    print_color $YELLOW "-------------------------------------------------------------"
    sleep 3
}

confirm() {
    while true; do
        read -p "$(print_color $YELLOW "$1 (y/n): ")" yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) print_color $RED "Please answer yes or no.";;
        esac
    done
}

get_input() {
    local prompt="$1"
    local input=""
    while [ -z "$input" ]; do
        read -p "$(print_color $YELLOW "$prompt: ")" input
        if [ -z "$input" ]; then
            print_color $RED "Input cannot be empty. Please try again."
        fi
    done
    echo "$input"
}

print_header

if ! command -v node &> /dev/null; then
    print_color $RED "Node.js is not installed. Please install Node.js and npm before continuing."
    exit 1
fi

print_color $GREEN "Cleaning up existing installation..."
rm -rf node_modules package-lock.json

print_color $GREEN "Initializing a new Node.js project..."
npm init -y

print_color $GREEN "Installing dependencies..."
npm install --save-dev hardhat @matterlabs/hardhat-zksync-solc @matterlabs/hardhat-zksync-deploy @matterlabs/hardhat-zksync-verify @nomicfoundation/hardhat-toolbox typescript ts-node @types/node zksync-web3 ethers@^6.12.2 zksync-ethers@^6.8.0 dotenv --legacy-peer-deps

npx hardhat init

print_color $GREEN "Creating tsconfig.json..."
cat > tsconfig.json << EOL
{
  "compilerOptions": {
    "target": "es2020",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "dist",
    "noImplicitAny": true,
    "resolveJsonModule": true
  },
  "include": ["./scripts", "./test", "./deploy"],
  "files": ["./hardhat.config.ts"]
}
EOL

INFURA_API_KEY=$(get_input "Enter your Infura API Key")

print_color $GREEN "Creating hardhat.config.ts..."
cat > hardhat.config.ts << EOL
import { HardhatUserConfig } from "hardhat/config";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-verify";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  zksolc: {
    version: "1.5.2",
    compilerSource: "binary",
    settings: {},
  },
  defaultNetwork: "abstractTestnet",
  networks: {
    hardhat: {
      zksync: false,
    },
    abstractTestnet: {
      url: "https://api.testnet.abs.xyz",
      ethNetwork: \`https://sepolia.infura.io/v3/\${process.env.INFURA_API_KEY}\`,
      zksync: true,
      verifyURL: 'https://api-explorer-verify.testnet.abs.xyz/contract_verification'
    },
  },
  solidity: {
    version: "0.8.17",
  },
};

export default config;
EOL

mkdir -p deploy
print_color $GREEN "Creating deploy script..."
cat > deploy/deploy.ts << EOL
import { Wallet, Provider } from "zksync-ethers";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import * as dotenv from "dotenv";

dotenv.config();

export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(\`Running deploy script for the Lock contract\`);

  const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || "";
  if (!PRIVATE_KEY) {
    throw new Error("Please set WALLET_PRIVATE_KEY in your .env file");
  }

  // Initialize the wallet.
  const provider = new Provider(hre.network.config.url);
  const wallet = new Wallet(PRIVATE_KEY, provider);

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet);
  const artifact = await deployer.loadArtifact("Lock");

  // Get the current timestamp
  const currentTimestamp = Math.floor(Date.now() / 1000);
  
  // Set unlock time to 1 hour from now
  const unlockTime = currentTimestamp + 3600;

  // Estimate contract deployment fee
  const deploymentFee = await deployer.estimateDeployFee(artifact, [unlockTime]);

  // Deploy this contract. The returned object will be of a \`Contract\` type, similarly to ones in \`ethers\`.
  const parsedFee = ethers.formatEther(deploymentFee.toString());
  console.log(\`The deployment is estimated to cost \${parsedFee} ETH\`);

  const lockContract = await deployer.deploy(artifact, [unlockTime]);

  //obtain the Constructor Arguments
  console.log("Constructor args:" + lockContract.interface.encodeDeploy([unlockTime]));

  // Show the contract info.
  const contractAddress = await lockContract.getAddress();
  console.log(\`\${artifact.contractName} was deployed to \${contractAddress}\`);
  
  // Save contract address and unlock time to .env file
  require('fs').appendFileSync('.env', \`\nCONTRACT_ADDRESS=\${contractAddress}\nUNLOCK_TIME=\${unlockTime}\n\`);
}
EOL

mkdir -p contracts
print_color $GREEN "Creating a sample Lock contract..."
cat > contracts/Lock.sol << EOL
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Lock {
    uint public unlockTime;
    address payable public owner;

    event Withdrawal(uint amount, uint when);

    constructor(uint _unlockTime) payable {
        require(
            block.timestamp < _unlockTime,
            "Unlock time should be in the future"
        );

        unlockTime = _unlockTime;
        owner = payable(msg.sender);
    }

    function withdraw() public {
        require(block.timestamp >= unlockTime, "You can't withdraw yet");
        require(msg.sender == owner, "You aren't the owner");

        emit Withdrawal(address(this).balance, block.timestamp);

        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }
}
EOL

WALLET_PRIVATE_KEY=$(get_input "Enter your wallet private key")

echo "WALLET_PRIVATE_KEY=$WALLET_PRIVATE_KEY" > .env
echo "INFURA_API_KEY=$INFURA_API_KEY" >> .env

print_color $GREEN "Compiling contracts..."
npx hardhat compile

if confirm "Do you want to deploy the contract?"; then
    print_color $GREEN "Deploying contract..."
    npx hardhat deploy-zksync --script deploy.ts --network abstractTestnet
fi

if confirm "Do you want to verify the contract?"; then
    source .env
    print_color $GREEN "Verifying contract..."
    npx hardhat verify --network abstractTestnet $CONTRACT_ADDRESS $UNLOCK_TIME
fi

sed -i '/WALLET_PRIVATE_KEY/d' .env
print_color $GREEN "Private key has been successfully removed from the .env file."

print_color $GREEN "Script execution completed."
print_color $BLUE "Join us on Twitter: https://x.com/0xoneiros"
read -p "$(print_color $YELLOW "Press Enter to exit...")"

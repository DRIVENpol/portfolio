
const ethers = require("ethers");
const dotenv = require("dotenv");
const axios = require('axios');

const TelegramBot = require("node-telegram-bot-api");

dotenv.config();

// SECRET VARIABLES
const bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { polling: true });
const key = process.env.PRIVATE_KEY;
const contractAddress = process.env.TOKEN_ADDRESS;
const pairAddress = process.env.PAIR_ADDRESS;
const wethAddress = process.env.WETH_ADDRESS;
const routerAddress = process.env.ROUTER_ADDRESS;
const hotWallet = process.env.HOT_WALLET;
const bscRpcUrl = process.env.BSC_PROVIDER;

// Test
const contractUSDT = process.env.TEST_TOKEN_ADDRESS;

const decimals = 9;

// Gifs
let gifWinner = "https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExZTAwYjkzOTNlY2E2ZjJkZDk1NjY0ZjA2NWMxY2IzNjk4Y2RiNjI4MiZlcD12MV9pbnRlcm5hbF9naWZzX2dpZklkJmN0PWc/vCJ9oGYB1ZDNKa7tZF/giphy-downsized-large.gif";
let gifLoser = "https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExMTA4ZWM0ZTZjODhiODFlMDhmNjBhYjBkNmU1ZWZmMDA4ZTFkMzllMSZlcD12MV9pbnRlcm5hbF9naWZzX2dpZklkJmN0PWc/EOP3eXJGWXmzkgF1cs/giphy-downsized-large.gif"

// Links
const linkText1 = 'Website';
const linkUrl1 = 'https://www.caacon.vip/';

const linkText2 = 'Twitter';
const linkUrl2 = 'https://twitter.com/Caaconofficial';

const linkText3 = 'Telegram';
const linkUrl3 = 'https://t.me/CaaconPortal';

// Provider object
const provider = new ethers.JsonRpcProvider(bscRpcUrl);

// Erc20 ABI
const erc20Abi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function transfer(address to, uint256 value) returns (bool)",
  "event Transfer(address indexed from, address indexed to, uint256 value)"
];

// Links 
const markdownLink1 = `[${linkText1}](${linkUrl1})`;
const markdownLink2 = `[${linkText2}](${linkUrl2})`;
const markdownLink3 = `[${linkText3}](${linkUrl3})`;

let ethPrice;
let tokenPriceInUSD = 0;

// Telegram group ID
const groupChatId = process.env.CHAT_ID;

// Contract object
const contract = new ethers.Contract(contractAddress, erc20Abi, provider);
//TODO: Disable on production
const contractTest = new ethers.Contract(contractUSDT, erc20Abi, provider);

// bot.on("message", (msg) => {
//   console.log(`Group chat ID: ${msg.chat.id}`);
// });


// Fetch the token price in eth
async function fetchTokenPriceInEth() {
  try {
    const tk_sc = new ethers.Contract(contractAddress, erc20Abi, provider);
    const weth_sc = new ethers.Contract(wethAddress, erc20Abi, provider);
  
    let balanceToken = await tk_sc.balanceOf(pairAddress);
    let balanceWeth = await weth_sc.balanceOf(pairAddress);
    
    let _balanceT = Number(balanceToken) / 10 ** 9;
    let _weth_value = Number(balanceWeth) * Number(ethPrice) / 10 ** 18;

    // console.log("balanceToken: " + balanceToken);
    // console.log("balanceWeth: " + balanceWeth);
    // console.log("_balanceT: " + _balanceT);
    // console.log("_weth_value: " + _weth_value);

    tokenPriceInUSD = _weth_value / _balanceT;
    // console.log("tokenPriceInUSD: " + tokenPriceInUSD); 
  } catch (error) {
    console.log("Error::fetchTokenPriceInEth" + error);
  }
}

// Function to generate x (count) random numbers
function generateUniqueRandomNumbers(count) {
  try {
    const numbers = new Set();
      while (numbers.size < count) {
        numbers.add(Math.floor(Math.random() * 100) + 1);
      }
    return Array.from(numbers);   
  } catch (error) {
    console.log("Error::generateUniqueRandomNumbers" + error);
  }
  }

// Fetch Eth price
async function fetchEthPrice() {
  try {
    // Use CoinGecko API endpoint
    let url = 'https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd';

    let response = await axios.get(url);
    let result = response.data;

    // Access ETH price in USD
    ethPrice = result.ethereum.usd;
    console.log('Price: ' + ethPrice);
  } catch (error) {
    console.error('Error fetching price:', error);
  }
}

// Listening to contract events
contractTest.on("Transfer", async (from, to, value, event) => {
  try {
    // console.log("Router: " + routerAddress);
    // console.log("From: " + from);
    // console.log('\n')
    // 0x6E476f91A303694064F1271DFCBf71A3bEd8A385


    // if (from == routerAddress) {
      if (
        from == "0x628d9A2175B66A11fcE8208106Fbb95Ed33503E0" &&
        to != "0xC39b0D3c3DA68cdaefe24a07373b9894496eCA97"
      ) {


    await fetchEthPrice();
    await fetchTokenPriceInEth();

    let hotWalletBalance = await provider.getBalance(hotWallet);

        console.log('\n')
        console.log("Catch buy!")
        console.log('\n')
      // See how many tokens were bought
      const tokenAmount = parseFloat(ethers.formatUnits(value, 18)).toFixed(1);

      // The core of the message
      let message = `🚀 New BUY! ${parseFloat(Number(value) / 10 ** decimals).toFixed(2)} Caacon tokens were bought from Uniswap!`;

      // Local price 
      let localPrice = 1;

      console.log("value: " + value);
      console.log("Number(value): " + Number(value));
      console.log("(Number(value) / 10 ** decimals): " + (Number(value) / 10 ** decimals));
      console.log("tokenPriceInUSD: " + tokenPriceInUSD);
      console.log("(Number(value) / 10 ** decimals) * tokenPriceInUSD" + (Number(value) / 10 ** decimals) * tokenPriceInUSD)

      let _x = (Number(value) / 10 ** decimals) * tokenPriceInUSD;
      
      let _dif = 0;

      if(_x > 97 && _x < 100 ) {
        _dif = 101 - _x;
      }

      if (_x +  _dif >= 100) {
      // TODO: Change on deployment
      // if (buyValue * tokenPriceInUSD >= 100) {

        console.log("\n");
        console.log("Generating probability...");
        console.log("\n");

        // TODO: Change - buyValue * localPrice
        const randomArrayLength = Math.min(Math.floor((_x +  _dif) / 100), 10);
        const randomNumbers = generateUniqueRandomNumbers(randomArrayLength);
        const randomNumberToCheck = Math.floor(Math.random() * 100) + 1;
        console.log("Probability generated!");
        console.log("\n");

        console.log("Random numbers: " + randomNumbers);
        console.log("Random number as reference: " + randomNumberToCheck);
        console.log("\n");

        let actualPot = Number(hotWalletBalance) / 2;
        let nextPot = Number(hotWalletBalance) / 4;
        console.log("actualPot: " + actualPot);
        console.log("nextPot: " + nextPot);
  
        if (randomNumbers.includes(randomNumberToCheck)) {
          message += `\n \n 🏆 WINNER 🏆 \n 🎰 Jackpot value: ${parseFloat(actualPot / 10 ** 18).toFixed(2)} ETH ($${parseFloat((actualPot  / 10 ** 18)* ethPrice).toFixed(1)}) \n ⏳ Next jackpot: ${parseFloat(nextPot / 10 ** 18).toFixed(2)} ETH ($${parseFloat((nextPot  / 10 ** 18)* ethPrice).toFixed(1)}) \n 💳 Buy amount: $${parseFloat(_x).toFixed(1)} \n 📊 Probability of win: ${randomArrayLength}% \n \n 🌐 ${markdownLink1} // 🐦 ${markdownLink2} // 📣 ${markdownLink3}`;
             await bot.sendAnimation(groupChatId, gifWinner, { caption: message, parse_mode: 'Markdown' });
     
             console.log("\n");
             console.log("Eth balance: " + hotWalletBalance);
             console.log("Pot: " + actualPot);
             console.log("Next pot: " + nextPot);
             console.log("\n");

             // CONNECT TO HOT WALLET
             console.log("\n");
             console.log("Connecting to hotwallet!");
             console.log("\n");
             const callerWallet = new ethers.Wallet(String(key), provider);
             console.log("Connected to hotwallet!");
             console.log("\n");

             // SEND POT
             console.log("\n");
             console.log("Sending reward...");
             console.log("\n");

            //  let tx = {
            //         to: to,
            //         value: actualPot
            //   }

            // DISABLE ON MAINNET
              let tx = {
                to: to,
                value: String(actualPot)
          }

              callerWallet.sendTransaction(tx)
              .then((txObj) => {
                    console.log('txHash', txObj.hash)
              })

             console.log("Reward sent: " + actualPot);
             console.log("\n");
        } else {
        message += `\n \n 🚫 You are not a winner \n 🎰 Jackpot value: ${parseFloat(actualPot / 10 ** 18).toFixed(2)} ETH ($${parseFloat((actualPot  / 10 ** 18)* ethPrice).toFixed(1)}) \n ⏳ Next jackpot: ${parseFloat(nextPot / 10 ** 18).toFixed(2)} ETH ($${parseFloat((nextPot  / 10 ** 18)* ethPrice).toFixed(1)}) \n 💳 Buy amount: $${parseFloat(_x).toFixed(1)} \n 📊 Probability of win: ${randomArrayLength}% \n \n 🌐 ${markdownLink1} // 🐦 ${markdownLink2} // 📣 ${markdownLink3}`;
            // await bot.sendMessage(groupChatId, message);
            await bot.sendAnimation(groupChatId, gifLoser, { caption: message, parse_mode: 'Markdown' });
        }
      }
    }  
  } catch (error) {
      console.log("Error: " + error);
    }
  });
  
  console.log("Bot is listening for buy events...");
const ethers = require('ethers');
const Excel = require('exceljs');
require("dotenv").config()

const factoryAbi = require('./JSON/factory.json');
const pairAbi = require('./JSON/pair.json');
const wbnbAbi = require('./JSON/wbnb.json');

// ENV variables
const provider = process.env.PROVIDER;
const key = process.env.PRIVATE_KEY;

// Variables
const pcsFactory = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73";
const busd = "0xe9e7cea3dedca5984780bafc599bd69add087d56";
const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";

let i = 0; // all events
let j = 0; // proper events

const MIN_BNB = 16000000000000000000; // 16 BNB
const MIN_BUSD = 5000000000000000000000; // 5,000 BUSD

const MAX_BNB = 116000000000000000000; // 116 BNB
const MAX_BUSD = 35000000000000000000; // 35,000 BUSD

const wb = new Excel.Workbook();
const ws = wb.addWorksheet('My Sheet');

const main = async () => {
    try {

        const fileName = 'bscFinds4.xlsx';
        ws.addRows([
            ["Pair Address", "Token Address", "Type", "Liquidity", "Chart"]]
        );

       // Wallet connection
        console.log("\n");
        console.log("\x1b[33m%s\x1b[0m", "CONNECTING TO WALLET...");

        const iProvider = new ethers.providers.JsonRpcProvider(provider);
        const callerWallet = new ethers.Wallet(String(key), iProvider);

        console.log("Connected!")
        console.log("\n");

        // Wallet connection
        console.log("\n");
        console.log("\x1b[33m%s\x1b[0m", "CONNECTING TO FACTORY...");

        let factory = new ethers.Contract(pcsFactory, factoryAbi, callerWallet);
        console.log("Connected!")
        console.log("\n");

        const getReserves = async (address) => {
            try {
                console.log("\n");
                console.log("\x1b[33m%s\x1b[0m", `${i}) FETCHING RESERVES FOR ` + address);
                console.log(`\n Total pairs: ${i} // Good pairs: ${j}`);
                console.log("\n");
                i++;
                let tokenAbi = ["function balanceOf(address account) public view returns (uint256)"];
                

               // Connect to BUSD & WBNB Smart Contract
               let busdSC = new ethers.Contract(busd, tokenAbi, callerWallet);
               let wbnbSc = new ethers.Contract(wbnb, wbnbAbi, callerWallet);
               let pairAddress =  new ethers.Contract(address, pairAbi, callerWallet);

                let wbnbBalance = await wbnbSc.balanceOf(address);
                let busdBalance = await busdSC.balanceOf(address);

                let token0 = await pairAddress.token0();
                let token1 = await pairAddress.token1();

                // if(wbnbBalance >= 0,01 * 10 ** 18) {
                //         console.log("WBNB Pair Found!");
                //         console.log("Token Address: " + token1);
                //         console.log("WBNB Reserves: " + wbnbBalance);
                //         console.log("\n");
                //         j++;
                // } else if (busdBalance >= 2 * 10 ** 18) {
                //         console.log("BUSD Pair Found!");
                //         console.log("Token Address: " + token0);
                //         console.log("BUSD Reserves: " + busdBalance);
                //         console.log("\n");
                //         j++;   
                // } else {
                //     console.log("Invalid reserves!")
                // }

                if(wbnbBalance != 0) {
                    if(String(token0) == wbnb && wbnbBalance >= MIN_BNB && wbnbBalance <= MAX_BNB) {
                        console.log("WBNB Pair Found!");
                        console.log("Token Address: " + token1);
                        console.log("WBNB Balance: " + String(wbnbBalance));
                        console.log("\n =============== LINKS =============== \n");
                        console.log("Link: " + `https://bscscan.com/token/${token1}`);
                        console.log("Chart: " + `https://poocoin.app/tokens/${token1}`);

                        ws.addRows([
                            [String(address), String(token1), "wBNB", String(wbnbBalance), `https://poocoin.app/tokens/${token1}`]]
                            );

                        wb.xlsx
                            .writeFile(fileName)
                            .then(() => {
                                console.log('[File created!]');
                            })
                            .catch(err => {
                                console.log(err.message);
                            });

                        console.log("\n \n");
                        j++;
                    } else if(String(token1) == wbnb && wbnbBalance >= MIN_BNB && wbnbBalance <= MAX_BNB) {
                        console.log("WBNB Pair Found!");
                        console.log("Token Address: " + token0);
                        console.log("WBNB Balance: " + String(wbnbBalance));
                        console.log("\n =============== LINKS =============== \n");
                        console.log("Link: " + `https://bscscan.com/token/${token0}`);
                        console.log("Chart: " + `https://poocoin.app/tokens/${token0}`);

                        ws.addRows([
                            [String(address), String(token0), "wBNB", String(wbnbBalance), `https://poocoin.app/tokens/${token0}`]]
                        );

                        wb.xlsx
                            .writeFile(fileName)
                            .then(() => {
                                console.log('[File created!]');
                            })
                            .catch(err => {
                                console.log(err.message);
                            });


                        console.log("\n \n");
                        j++;  
                    }

                } else if (busdBalance != 0 && busdBalance >= MIN_BUSD && busdBalance <= MAX_BUSD) {
                    if(String(token0) == busd) {
                        console.log("BUSD Pair Found!");
                        console.log("Token Address: " + token1);
                        console.log("BUSD Reserves: " + String(busdBalance));
                        console.log("\n =============== LINKS =============== \n");
                        console.log("Link: " + `https://bscscan.com/token/${token1}`);
                        console.log("Chart: " + `https://poocoin.app/tokens/${token1}`);

                        ws.addRows([
                            [String(address), String(token1), "BUSD", String(busdBalance), `https://poocoin.app/tokens/${token1}`]]
                            );

                        wb.xlsx
                            .writeFile(fileName)
                            .then(() => {
                                console.log('[File created!]');
                            })
                            .catch(err => {
                                console.log(err.message);
                            });


                        console.log("\n \n");
                        j++;  
                    } else if(String(token1) == busd) {
                        console.log("BUSD Pair Found!");
                        console.log("Token Address: " + token0);
                        console.log("BUSD Reserves: " + String(busdBalance));
                        console.log("\n =============== LINKS =============== \n");
                        console.log("Link: " + `https://bscscan.com/token/${token0}`);
                        console.log("Chart: " + `https://poocoin.app/tokens/${token0}`);

                        ws.addRows([
                            [String(address), String(token0), "BUSD", String(busdBalance), `https://poocoin.app/tokens/${token0}`]]
                            );

                        wb.xlsx
                            .writeFile(fileName)
                            .then(() => {
                                console.log('[File created!]');
                            })
                            .catch(err => {
                                console.log(err.message);
                            });

                        console.log("\n \n");
                        j++;    
                    }
                } else {console.log("Invalid!")}

            } catch (error) {
                console.log("Err getReserves function: " + error);
            }
        }

        console.log("\n");
        console.log("\x1b[33m%s\x1b[0m", "LISTENING ON EVENTS ...");

        factory.on("PairCreated", (token0, token1, pair, allPairs) => {
            let info = {
              token0: token0,
              token1: token1,
              pair: pair,
              allPairs: allPairs,
            };

            getReserves(String(info.pair))
          });


    } catch (error) {
        console.log("Err! " + error);
    }
}

main();
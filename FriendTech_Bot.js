const ethers = require('ethers');
const dotenv = require('dotenv');
const fs = require('fs');

dotenv.config();

const friendsTechABI = require('./ftech.json');

const PROVIDER = process.env.BASE_PROVIDER;
const KEY = process.env.PRIVATE_KEY;
const provider = new ethers.WebSocketProvider(PROVIDER);
const wallet = new ethers.Wallet(String(KEY), provider);

const ftechAddr = "0xCF205808Ed36593aa40a44F10c7f7C2F67d4A4d4";
const newABI = [
    "function buyShares(address sharesSubject, uint256 amount) public payable",
    "function getBuyPriceAfterFee(address _subject, uint256 _amount) view returns (uint256)",
    "function getSellPriceAfterFee(address _subject, uint256 _amount) view returns (uint256)",
    "function getPrice(uint256 _supply, uint256 _amount) view returns (uint256)",
    "function protocolFeePercent() view returns (uint256)",
    "function subjectFeePercent() view returns (uint256)",
    "event Trade(address trader, address subject, bool isBuy, uint256 shareAmount, uint256 ethAmount, uint256 protocolEthAmount, uint256 subjectEthAmount, uint256 supply)"
];
const ftech = new ethers.Contract(ftechAddr, newABI, wallet);
// console.log("Abi:", friendsTechABI);
// console.log("Contract:", ftech);

async function buy_shares(address, amount, supply) {
    try {
        // const estimatedGas = await ftech.estimateGas.buyShares(address, amount);
        let _bp = BigInt(await ftech.getPrice(supply, "1"));
        let _pf = BigInt(_bp) * BigInt(await ftech.protocolFeePercent()) / BigInt(1e18);
        let _sf = BigInt(_bp) * BigInt(await ftech.subjectFeePercent()) / BigInt(1e18);
        let _tf = _bp + _pf + _sf;
        let buy_price = await get_Price_After_Fee_Buy(address, "1");
        const tx = await ftech.buyShares(address, amount, {value: _tf});
        await tx.wait();

        const characteristics = {
            buy_price: ethers.formatEther(buy_price),
            status: "bought",
            supply: supply.toString(),
        };

        writeSubjectsToFile(address, characteristics);
        return true;
    } catch (error) {
        console.error("Error pushing transaction:", error);
        return false;
    }
}

async function get_Price_After_Fee_Buy(addr, amount) {
    const price = await ftech.getBuyPriceAfterFee(addr, amount);
    return price;
}

async function get_Price_After_Fee_Sell(addr, amount) {
    const price = await ftech.getSellPriceAfterFee(addr, amount);
    return ethers.formatEther(price);
}

async function subjectExistsInFile(subject) {
    try {
        const data = fs.readFileSync('subjects.json', 'utf8');
        const subjectsFromFile = JSON.parse(data);

        const data2 = fs.readFileSync('subjects_temp.json', 'utf8');
        const subjectsFromTempFile = JSON.parse(data2);
        return subjectsFromFile[subject] && subjectsFromTempFile[subject] ? true : false;
    } catch (error) {
        return false;
    }
}

function writeSubjectsToFile(subject, characteristics) {
    let subjectsFromFile = {};

    try {
        const data = fs.readFileSync('subjects.json', 'utf8');
        subjectsFromFile = JSON.parse(data);
    } catch (error) {
        console.error('Error reading from file:', error);
    }

    subjectsFromFile[subject] = characteristics;

    const tmpFileName = 'subjects_temp.json';

    try {
        fs.writeFileSync(tmpFileName, JSON.stringify(subjectsFromFile, null, 4));
    } catch (err) {
        console.error('Error writing to temporary file:', err);
        return;
    }

    try {
        fs.renameSync(tmpFileName, 'subjects.json');
    } catch (err) {
        console.error('Error renaming the temporary file:', err);
    }
}


async function main() {
    console.log("Looking for events 👀 ...");

    ftech.on("Trade", async (
        trader, 
        subject, 
        isBuy, 
        shareAmount, 
        ethAmount, 
        protocolEthAmount,
        subjectEthAmount,
        supply
    ) => {
        if(!isBuy) return;
        if(supply > 12) return;
        if(supply < 10) return;
        console.log("Trade event detected!");
        console.log("Supply:", supply.toString());

        if(await subjectExistsInFile(subject)) return;

        let sell_price = await get_Price_After_Fee_Sell(subject, "1");

        // console.log("Buy Price:", ethers.formatEther(buy_price));
        // if (ethers.formatEther(buy_price) > 0.005) return;
            let success = await buy_shares(subject, "1", supply);
            if(!success) {
                console.error("Error buying shares!");
                return;
            };
            console.log("Success! 🚀🚀🚀🚀🚀🚀🚀🚀🚀");


        // console.log("\n");
        // console.log("NEW BUY DETECTED 🚀🚀🚀🚀🚀🚀🚀🚀🚀");
        // console.log("---------------------------------------");
        // console.log("Subject Address:               ", subject);
        // console.log("Share Supply:                  ", supply.toString());
        // console.log("Buy Price:                     ", ethers.formatEther(buy_price));
        // console.log("Sell Price:                    ", sell_price);
        // console.log("---------------------------------------");
        // console.log("\n");
    });
}

main();

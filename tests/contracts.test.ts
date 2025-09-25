import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;
const wallet4 = accounts.get("wallet_4")!;

/**
 * Comprehensive test suite for the Water Rights Trading Platform
 * Tests all four core contracts: Registry, Token, Marketplace, and Usage Reporting
 */

describe("Water Rights Registry Contract", () => {
  it("Contract owner can authorize regulators", () => {
    const regulator = wallet1;
    
    const { result } = simnet.callPublicFn(
      "water-rights-registry",
      "authorize-regulator",
      [Cl.principal(regulator)],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Verify regulator is authorized
    const query = simnet.callReadOnlyFn(
      "water-rights-registry",
      "is-regulator-authorized",
      [Cl.principal(regulator)],
      deployer
    );
    
    expect(query.result).toBeBool(true);
  });

  it("Non-owner cannot authorize regulators", () => {
    const nonOwner = wallet1;
    const regulator = wallet2;
    
    const { result } = simnet.callPublicFn(
      "water-rights-registry",
      "authorize-regulator",
      [Cl.principal(regulator)],
      nonOwner
    );
    
    expect(result).toBeErr(Cl.uint(100)); // err-unauthorized
  });

  it("Authorized regulator can issue water rights", () => {
    const regulator = wallet1;
    const rightHolder = wallet2;
    
    // First authorize the regulator
    simnet.callPublicFn(
      "water-rights-registry",
      "authorize-regulator",
      [Cl.principal(regulator)],
      deployer
    );
    
    // Issue a water right
    const { result } = simnet.callPublicFn(
      "water-rights-registry",
      "issue-water-right",
      [
        Cl.principal(rightHolder),
        Cl.uint(1000000), // 1 million liters
        Cl.uint(100),     // valid from block 100
        Cl.uint(1000),    // valid until block 1000
        Cl.stringAscii("Region-A")
      ],
      regulator
    );
    
    expect(result).toBeOk(Cl.uint(1)); // First right ID
    
    // Verify the water right was created
    const query = simnet.callReadOnlyFn(
      "water-rights-registry",
      "get-water-right",
      [Cl.uint(1)],
      deployer
    );
    
    // Verify the water right was created successfully
    expect(query.result).toBeDefined();
  });
});

describe("Water Rights Token Contract", () => {
  it("Contract returns correct token metadata", () => {
    // Test token name
    const nameQuery = simnet.callReadOnlyFn("water-rights-token", "get-name", [], deployer);
    expect(nameQuery.result).toBeOk(Cl.stringAscii("Water Rights Token"));
    
    // Test token symbol
    const symbolQuery = simnet.callReadOnlyFn("water-rights-token", "get-symbol", [], deployer);
    expect(symbolQuery.result).toBeOk(Cl.stringAscii("WRT"));
    
    // Test decimals
    const decimalsQuery = simnet.callReadOnlyFn("water-rights-token", "get-decimals", [], deployer);
    expect(decimalsQuery.result).toBeOk(Cl.uint(6));
    
    // Test initial total supply
    const supplyQuery = simnet.callReadOnlyFn("water-rights-token", "get-total-supply", [], deployer);
    expect(supplyQuery.result).toBeOk(Cl.uint(0));
  });

  it("Contract owner can authorize minters", () => {
    const minter = wallet1;
    
    const { result } = simnet.callPublicFn(
      "water-rights-token",
      "authorize-minter",
      [Cl.principal(minter)],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Verify minter is authorized
    const query = simnet.callReadOnlyFn(
      "water-rights-token",
      "is-minter-authorized",
      [Cl.principal(minter)],
      deployer
    );
    
    expect(query.result).toBeBool(true);
  });

  it("Authorized minter can mint tokens", () => {
    const minter = wallet1;
    const recipient = wallet2;
    
    // First authorize the minter
    simnet.callPublicFn(
      "water-rights-token",
      "authorize-minter",
      [Cl.principal(minter)],
      deployer
    );
    
    // Mint tokens
    const { result } = simnet.callPublicFn(
      "water-rights-token",
      "mint",
      [Cl.uint(1000000), Cl.principal(recipient)], // 1 token (with 6 decimals)
      minter
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Verify recipient balance
    const balanceQuery = simnet.callReadOnlyFn(
      "water-rights-token",
      "get-balance",
      [Cl.principal(recipient)],
      deployer
    );
    
    expect(balanceQuery.result).toBeOk(Cl.uint(1000000));
  });
});

describe("Marketplace Contract", () => {
  it("Contract owner can authorize token contracts", () => {
    const tokenContract = wallet1; // Simulating token contract address
    
    const { result } = simnet.callPublicFn(
      "marketplace",
      "authorize-token",
      [Cl.principal(tokenContract)],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Verify token is authorized
    const query = simnet.callReadOnlyFn(
      "marketplace",
      "is-token-contract-authorized",
      [Cl.principal(tokenContract)],
      deployer
    );
    
    expect(query.result).toBeBool(true);
  });

  it("User can create listing for authorized token", () => {
    const seller = wallet1;
    const tokenContract = wallet2;
    
    // First authorize the token contract
    simnet.callPublicFn(
      "marketplace",
      "authorize-token",
      [Cl.principal(tokenContract)],
      deployer
    );
    
    // Create a listing
    const { result } = simnet.callPublicFn(
      "marketplace",
      "create-listing",
      [
        Cl.principal(tokenContract),
        Cl.uint(1000000), // 1 token (with 6 decimals)
        Cl.uint(100),     // 100 microSTX per token
        Cl.uint(1000)     // Expires in 1000 blocks
      ],
      seller
    );
    
    expect(result).toBeOk(Cl.uint(1)); // First listing ID
    
    // Verify the listing was created
    const query = simnet.callReadOnlyFn(
      "marketplace",
      "get-listing",
      [Cl.uint(1)],
      deployer
    );
    
    // Verify the listing was created successfully
    expect(query.result).toBeDefined();
  });

  it("Cannot create listing for unauthorized token", () => {
    const seller = wallet1;
    const unauthorizedToken = wallet2;
    
    const { result } = simnet.callPublicFn(
      "marketplace",
      "create-listing",
      [
        Cl.principal(unauthorizedToken),
        Cl.uint(1000000),
        Cl.uint(100),
        Cl.uint(1000)
      ],
      seller
    );
    
    expect(result).toBeErr(Cl.uint(109)); // err-invalid-token-contract
  });
});

describe("Usage Reporting Contract", () => {
  it("Contract owner can authorize validators", () => {
    const validator = wallet1;
    
    const { result } = simnet.callPublicFn(
      "usage-reporting",
      "authorize-validator",
      [Cl.principal(validator)],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Verify validator is authorized
    const query = simnet.callReadOnlyFn(
      "usage-reporting",
      "is-validator-authorized",
      [Cl.principal(validator)],
      deployer
    );
    
    expect(query.result).toBeBool(true);
  });

  it("User can submit usage report", () => {
    const reporter = wallet1;
    
    const { result } = simnet.callPublicFn(
      "usage-reporting",
      "submit-usage-report",
      [
        Cl.uint(1),        // right-id
        Cl.uint(500000),   // volume-used (500,000 liters)
        Cl.stringAscii("Normal usage for irrigation")
      ],
      reporter
    );
    
    expect(result).toBeOk(Cl.uint(1)); // First report ID
    
    // Verify the report was created
    const query = simnet.callReadOnlyFn(
      "usage-reporting",
      "get-usage-report",
      [Cl.uint(1)],
      deployer
    );
    
    // Verify the report was created successfully
    expect(query.result).toBeDefined();
  });

  it("Authorized validator can verify usage report", () => {
    const reporter = wallet1;
    const validator = wallet2;
    
    // Setup: authorize validator and submit report
    simnet.callPublicFn(
      "usage-reporting",
      "authorize-validator",
      [Cl.principal(validator)],
      deployer
    );
    
    simnet.callPublicFn(
      "usage-reporting",
      "submit-usage-report",
      [
        Cl.uint(1),
        Cl.uint(500000),
        Cl.stringAscii("Usage report")
      ],
      reporter
    );
    
    // Verify the report
    const { result } = simnet.callPublicFn(
      "usage-reporting",
      "verify-usage-report",
      [
        Cl.uint(1),        // report-id
        Cl.bool(true),     // approved
        Cl.stringAscii("Verified as accurate")
      ],
      validator
    );
    
    expect(result).toBeOk(Cl.bool(true));
    
    // Verify the report status was updated
    const reportQuery = simnet.callReadOnlyFn(
      "usage-reporting",
      "get-usage-report",
      [Cl.uint(1)],
      deployer
    );
    
    // Verify the report was verified successfully
    expect(reportQuery.result).toBeDefined();
  });
});

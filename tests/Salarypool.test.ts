import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("Salary Vesting DAO Contract", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
  });

  describe("Contract Initialization", () => {
    it("should initialize with correct owner", () => {
      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "get-contract-owner",
        [],
        deployer
      );
      expect(result).toBeOk(Cl.principal(deployer));
    });

    it("should not be paused initially", () => {
      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "is-emergency-paused",
        [],
        deployer
      );
      expect(result).toBeBool(false);
    });

    it("should have zero vesting schedules initially", () => {
      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "get-total-vesting-schedules",
        [],
        deployer
      );
      expect(result).toBeUint(0);
    });
  });

  describe("Vesting Schedule Creation", () => {
    it("should allow owner to create vesting schedule", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(1000000), // 1 STX total
          Cl.uint(144), // ~1 day interval (144 blocks)
          Cl.uint(100000), // 0.1 STX per period
        ],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should not allow non-owner to create vesting schedule", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet2),
          Cl.uint(1000000),
          Cl.uint(144),
          Cl.uint(100000),
        ],
        wallet1
      );
      expect(result).toBeErr(Cl.uint(401)); // ERR-NOT-AUTHORIZED
    });

    it("should not allow creating duplicate vesting schedule", () => {
      // Create first schedule
      simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(144),
          Cl.uint(100000),
        ],
        deployer
      );

      // Try to create duplicate
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(2000000),
          Cl.uint(288),
          Cl.uint(200000),
        ],
        deployer
      );
      expect(result).toBeErr(Cl.uint(407)); // ERR-ALREADY-EXISTS
    });

    it("should validate vesting parameters", () => {
      // Test zero total
      let result = simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(0),
          Cl.uint(144),
          Cl.uint(100000),
        ],
        deployer
      );
      expect(result.result).toBeErr(Cl.uint(406)); // ERR-INVALID-AMOUNT

      // Test zero interval
      result = simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet2),
          Cl.uint(1000000),
          Cl.uint(0),
          Cl.uint(100000),
        ],
        deployer
      );
      expect(result.result).toBeErr(Cl.uint(408)); // ERR-INVALID-PARAMETERS

      // Test zero step
      result = simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet3),
          Cl.uint(1000000),
          Cl.uint(144),
          Cl.uint(0),
        ],
        deployer
      );
      expect(result.result).toBeErr(Cl.uint(408)); // ERR-INVALID-PARAMETERS
    });
  });

  describe("Fund Management", () => {
    it("should allow anyone to deposit funds", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "deposit-funds",
        [Cl.uint(5000000)], // 5 STX
        wallet1
      );
      expect(result).toBeOk(Cl.uint(5000000));
    });

    it("should track contract balance correctly", () => {
      // Deposit funds
      simnet.callPublicFn(
        "Salarypool",
        "deposit-funds",
        [Cl.uint(3000000)],
        wallet1
      );

      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "get-contract-balance",
        [],
        deployer
      );
      expect(result).toBeUint(3000000);
    });

    it("should allow owner to withdraw excess funds", () => {
      // First deposit funds
      simnet.callPublicFn(
        "Salarypool",
        "deposit-funds",
        [Cl.uint(2000000)],
        deployer
      );

      // Then withdraw
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "withdraw-excess-funds",
        [Cl.uint(1000000)],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1000000));
    });

    it("should not allow non-owner to withdraw funds", () => {
      simnet.callPublicFn(
        "Salarypool",
        "deposit-funds",
        [Cl.uint(2000000)],
        deployer
      );

      const { result } = simnet.callPublicFn(
        "Salarypool",
        "withdraw-excess-funds",
        [Cl.uint(1000000)],
        wallet1
      );
      expect(result).toBeErr(Cl.uint(401)); // ERR-NOT-AUTHORIZED
    });
  });

  describe("Token Claiming", () => {
    beforeEach(() => {
      // Setup: deposit funds and create vesting schedule
      simnet.callPublicFn(
        "Salarypool",
        "deposit-funds",
        [Cl.uint(10000000)], // 10 STX
        deployer
      );

      simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(1000000), // 1 STX total
          Cl.uint(1), // 1 block interval for testing
          Cl.uint(100000), // 0.1 STX per block
        ],
        deployer
      );
    });

    it("should allow claiming vested tokens", () => {
      // Mine some blocks to make tokens vest
      simnet.mineEmptyBlocks(5);

      const { result } = simnet.callPublicFn(
        "Salarypool",
        "claim-vested",
        [],
        wallet1
      );
      expect(result).toBeOk(Cl.uint(500000)); // 5 blocks * 0.1 STX
    });

    it("should not allow claiming when nothing is vested", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "claim-vested",
        [],
        wallet1
      );
      expect(result).toBeErr(Cl.uint(409)); // ERR-NOTHING-TO-CLAIM
    });

    it("should not allow claiming without vesting schedule", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "claim-vested",
        [],
        wallet2
      );
      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });
  });

  describe("Read-only Functions", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(144),
          Cl.uint(100000),
        ],
        deployer
      );
    });

    it("should return vesting schedule", () => {
      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "get-vesting-schedule",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeSome();
    });

    it("should return none for non-existent schedule", () => {
      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "get-vesting-schedule",
        [Cl.principal(wallet2)],
        deployer
      );
      expect(result).toBeNone();
    });

    it("should check if recipient has active vesting", () => {
      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "has-active-vesting",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeBool(true);
    });

    it("should return claimable amount", () => {
      // Mine blocks to vest some tokens
      simnet.mineEmptyBlocks(2);

      const { result } = simnet.callReadOnlyFn(
        "Salarypool",
        "get-claimable-amount",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeSome();
    });
  });

  describe("Emergency Functions", () => {
    it("should allow owner to pause contract", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "emergency-pause-contract",
        [],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify contract is paused
      const pauseStatus = simnet.callReadOnlyFn(
        "Salarypool",
        "is-emergency-paused",
        [],
        deployer
      );
      expect(pauseStatus.result).toBeBool(true);
    });

    it("should prevent operations when paused", () => {
      // Pause contract
      simnet.callPublicFn("Salarypool", "emergency-pause-contract", [], deployer);

      // Try to create vesting schedule
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(144),
          Cl.uint(100000),
        ],
        deployer
      );
      expect(result).toBeErr(Cl.uint(405)); // ERR-EMERGENCY-PAUSE
    });

    it("should allow owner to resume contract", () => {
      // Pause then resume
      simnet.callPublicFn("Salarypool", "emergency-pause-contract", [], deployer);
      
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "emergency-resume-contract",
        [],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify contract is not paused
      const pauseStatus = simnet.callReadOnlyFn(
        "Salarypool",
        "is-emergency-paused",
        [],
        deployer
      );
      expect(pauseStatus.result).toBeBool(false);
    });

    it("should allow owner to transfer ownership", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "set-contract-owner",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify new owner
      const newOwner = simnet.callReadOnlyFn(
        "Salarypool",
        "get-contract-owner",
        [],
        deployer
      );
      expect(newOwner.result).toBeOk(Cl.principal(wallet1));
    });
  });

  describe("Batch Operations", () => {
    it("should create multiple vesting schedules", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "create-multiple-vestings",
        [
          Cl.list([Cl.principal(wallet1), Cl.principal(wallet2)]),
          Cl.list([Cl.uint(1000000), Cl.uint(2000000)]),
          Cl.list([Cl.uint(144), Cl.uint(288)]),
          Cl.list([Cl.uint(100000), Cl.uint(200000)]),
        ],
        deployer
      );
      expect(result).toBeOk();

      // Verify schedules were created
      const schedule1 = simnet.callReadOnlyFn(
        "Salarypool",
        "get-vesting-schedule",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(schedule1.result).toBeSome();

      const schedule2 = simnet.callReadOnlyFn(
        "Salarypool",
        "get-vesting-schedule",
        [Cl.principal(wallet2)],
        deployer
      );
      expect(schedule2.result).toBeSome();
    });

    it("should validate batch parameters", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "create-multiple-vestings",
        [
          Cl.list([Cl.principal(wallet1), Cl.principal(wallet2)]),
          Cl.list([Cl.uint(1000000)]), // Mismatched length
          Cl.list([Cl.uint(144), Cl.uint(288)]),
          Cl.list([Cl.uint(100000), Cl.uint(200000)]),
        ],
        deployer
      );
      expect(result).toBeErr(Cl.uint(408)); // ERR-INVALID-PARAMETERS
    });
  });

  describe("Vesting Cancellation", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Salarypool",
        "create-vesting",
        [
          Cl.principal(wallet1),
          Cl.uint(1000000),
          Cl.uint(144),
          Cl.uint(100000),
        ],
        deployer
      );
    });

    it("should allow owner to cancel vesting", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "cancel-vesting",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));

      // Verify vesting is inactive
      const hasActive = simnet.callReadOnlyFn(
        "Salarypool",
        "has-active-vesting",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(hasActive.result).toBeBool(false);
    });

    it("should not allow non-owner to cancel vesting", () => {
      const { result } = simnet.callPublicFn(
        "Salarypool",
        "cancel-vesting",
        [Cl.principal(wallet1)],
        wallet2
      );
      expect(result).toBeErr(Cl.uint(401)); // ERR-NOT-AUTHORIZED
    });
  });
});
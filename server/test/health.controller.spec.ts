import { Test, TestingModule } from "@nestjs/testing";
import { ConfigModule } from "@nestjs/config";

import { HealthController } from "../src/health.controller";

describe("HealthController", () => {
  let controller: HealthController;

  beforeAll(async () => {
    process.env.APP_ENV = "test";

    const module: TestingModule = await Test.createTestingModule({
      imports: [ConfigModule.forRoot({ isGlobal: true, ignoreEnvFile: true })],
      controllers: [HealthController],
    }).compile();

    controller = module.get<HealthController>(HealthController);
  });

  afterAll(() => {
    delete process.env.APP_ENV;
  });

  it("returns a healthy payload", () => {
    const health = controller.getHealth();

    expect(health.status).toBe("ok");
    expect(health.service).toBe("inhouse-maker-server");
    expect(health.environment).toBe("test");
    expect(health.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });
});

import { Controller, Get } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

interface HealthResponse {
  service: string;
  status: "ok";
  environment: string;
  timestamp: string;
}

@Controller("health")
export class HealthController {
  constructor(private readonly configService: ConfigService) {}

  @Get()
  getHealth(): HealthResponse {
    return {
      service: "inhouse-maker-server",
      status: "ok",
      environment:
        this.configService.get<string>("APP_ENV") ??
        this.configService.get<string>("NODE_ENV") ??
        "development",
      timestamp: new Date().toISOString(),
    };
  }
}

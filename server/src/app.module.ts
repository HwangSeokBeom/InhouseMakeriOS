import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";

import { HealthController } from "./health.controller";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: [`.env.${process.env.NODE_ENV ?? "development"}`, ".env"],
    }),
  ],
  controllers: [HealthController],
})
export class AppModule {}

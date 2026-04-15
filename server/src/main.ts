import { Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { NestFactory } from "@nestjs/core";

import { AppModule } from "./app.module";

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  app.enableShutdownHooks();

  const configService = app.get(ConfigService);
  const port = Number(configService.get<string>("PORT") || 3000);
  const globalPrefix = configService.get<string>("GLOBAL_PREFIX")?.trim();

  if (globalPrefix) {
    app.setGlobalPrefix(globalPrefix);
  }

  await app.listen(port, "0.0.0.0");

  const logger = new Logger("Bootstrap");
  logger.log(`Server is running on port ${port}`);
}

void bootstrap();

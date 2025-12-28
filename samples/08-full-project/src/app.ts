// Main application
import { config } from './config';

export function main(): void {
    console.log(`Starting ${config.name} v${config.version}`);
}

main();

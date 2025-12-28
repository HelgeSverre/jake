// Utility functions
export function formatDate(date: Date): string {
    return date.toISOString();
}

export function log(msg: string): void {
    console.log(`[LOG] ${msg}`);
}

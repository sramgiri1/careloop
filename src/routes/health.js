export default async function health(app) {
  app.get("/health", { config: { public: true } }, async () => ({ status: "ok" }));
}

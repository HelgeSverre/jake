# Website related Jake tasks

# Domain for the website
domain "jakefile.dev"

@group web
@desc "Start website dev server"
task dev:
    @cd site
    @needs npm
    npm run dev

@group web
@desc "Build website for production"
task build:
    @cd site
    @needs npm
    npm run build

@group web
@desc "Deploy {{website} to production"
@needs vc "Install Vercel CLI: npm i -g vercel" -> "npm i -g vercel"
task deploy:
    @cd site
    @confirm "Deploy to production?"
    vc --prod --yes

@group web
@desc "Preview website deployment"
task preview:
    @cd site
    @needs vc "Install Vercel CLI: npm i -g vercel"
    vc --yes

# Website related Jake tasks

# Domain for the website
domain "jakefile.dev"

@group web
@desc "Start website dev server"
task dev: [editors.build-highlighters]
    @cd site
    @needs npm
    npm run dev

@group web
@desc "Build website for production"
task build: [editors.build-highlighters]
    @cd site
    @needs npm
    npm run build

## todo: variables should expand in desc strings

@group web
@desc "Deploy website to production"
@needs vc "Install Vercel CLI: npm i -g vercel" -> _install-vercel
task deploy:
    @cd site
    @confirm "Deploy to production?"
    vc --prod --yes

@group web
@desc "Preview website deployment"
@needs vc "Install Vercel CLI: npm i -g vercel" -> _install-vercel
task preview:
    @cd site
    vc --yes

# Private helper to install Vercel CLI
@quiet
task _install-vercel:
    npm i -g vercel

use std::io::Write;
use std::time::Duration;

use crossterm::event::Event;
use crossterm::event::KeyCode;
use crossterm::event::KeyEvent;
use crossterm::event::KeyModifiers;
use crossterm::event::{self};
use crossterm::execute;
use ratatui::backend::Backend;
use ratatui::layout::Constraint;
use ratatui::layout::Layout;
use ratatui::layout::Rect;
use ratatui::style::Stylize;
use ratatui::text::Line;
use ratatui::text::Span;
use ratatui::widgets::Block;
use ratatui::widgets::Borders;
use ratatui::widgets::List;
use ratatui::widgets::ListItem;
use ratatui::widgets::Paragraph;
use ratatui::widgets::Widget;

use super::WizardResult;
use super::validation;
use crate::custom_terminal::Frame;
use crate::custom_terminal::Terminal;

const REGIONS: &[(&str, &str)] = &[
    ("us-east-1", "US East (N. Virginia)"),
    ("us-east-2", "US East (Ohio)"),
    ("us-west-2", "US West (Oregon)"),
    ("eu-west-1", "Europe (Ireland)"),
    ("eu-west-2", "Europe (London)"),
    ("eu-central-1", "Europe (Frankfurt)"),
    ("eu-north-1", "Europe (Stockholm)"),
    ("eu-south-1", "Europe (Milan)"),
    ("ap-northeast-1", "Asia Pacific (Tokyo)"),
    ("ap-south-1", "Asia Pacific (Mumbai)"),
    ("ap-southeast-3", "Asia Pacific (Jakarta)"),
    ("sa-east-1", "South America (São Paulo)"),
];

#[derive(Clone, PartialEq, Eq)]
enum WizardStep {
    AuthMethod,
    ApiKeyEntry,
    RegionSelect,
    Validating,
    ModelSelect,
    Summary,
    Done,
}

struct BedrockSetupWizard {
    step: WizardStep,
    api_key: String,
    env_key_detected: bool,
    selected_region_index: usize,
    available_models: Vec<String>,
    selected_model_index: usize,
    error_message: Option<String>,
    quit: bool,
}

impl BedrockSetupWizard {
    fn new() -> Self {
        Self {
            step: WizardStep::AuthMethod,
            api_key: String::new(),
            env_key_detected: false,
            selected_region_index: 0,
            available_models: Vec::new(),
            selected_model_index: 0,
            error_message: None,
            quit: false,
        }
    }

    fn selected_region(&self) -> &str {
        REGIONS[self.selected_region_index].0
    }

    fn selected_model(&self) -> &str {
        &self.available_models[self.selected_model_index]
    }

    fn render(&self, frame: &mut Frame) {
        let area = frame.area();
        let block = Block::default()
            .title(" codex-b Setup ")
            .borders(Borders::ALL);
        let inner = block.inner(area);
        Widget::render(block, area, frame.buffer);

        match &self.step {
            WizardStep::AuthMethod => self.render_auth_method(frame, inner),
            WizardStep::ApiKeyEntry => self.render_api_key_entry(frame, inner),
            WizardStep::RegionSelect => self.render_region_select(frame, inner),
            WizardStep::Validating => self.render_validating(frame, inner),
            WizardStep::ModelSelect => self.render_model_select(frame, inner),
            WizardStep::Summary => self.render_summary(frame, inner),
            WizardStep::Done => {}
        }
    }

    fn render_auth_method(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::vertical([Constraint::Length(2), Constraint::Min(0)]).split(area);

        Widget::render(
            Paragraph::new("Select authentication method:"),
            chunks[0],
            frame.buffer,
        );

        let items: Vec<ListItem> = vec![
            ListItem::new(Line::from(vec!["> ".cyan(), "Bedrock API Key".into()])),
            ListItem::new(Line::from("  AWS Profile (coming soon)".dim())),
        ];
        Widget::render(List::new(items), chunks[1], frame.buffer);
    }

    fn render_api_key_entry(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::vertical([
            Constraint::Length(2),
            Constraint::Length(1),
            Constraint::Min(0),
        ])
        .split(area);

        let header = if self.env_key_detected {
            Paragraph::new("API key detected from environment. Press Enter to use it.")
        } else {
            Paragraph::new("Enter your Bedrock API key:")
        };
        Widget::render(header, chunks[0], frame.buffer);

        let masked: String = "•".repeat(self.api_key.len());
        let input_line = Paragraph::new(Line::from(vec!["> ".cyan(), Span::from(masked)]));
        Widget::render(input_line, chunks[1], frame.buffer);

        if let Some(err) = &self.error_message {
            Widget::render(
                Paragraph::new(Line::from(err.as_str().red())),
                chunks[2],
                frame.buffer,
            );
        }
    }

    fn render_region_select(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::vertical([
            Constraint::Length(2),
            Constraint::Min(0),
            Constraint::Length(1),
        ])
        .split(area);

        Widget::render(
            Paragraph::new("Select your Bedrock region:"),
            chunks[0],
            frame.buffer,
        );

        let items: Vec<ListItem> = REGIONS
            .iter()
            .enumerate()
            .map(|(i, (code, label))| {
                if i == self.selected_region_index {
                    ListItem::new(Line::from(vec![
                        "> ".cyan(),
                        (*code).into(),
                        " - ".dim(),
                        (*label).dim(),
                    ]))
                } else {
                    ListItem::new(Line::from(vec![
                        "  ".into(),
                        (*code).into(),
                        " - ".dim(),
                        (*label).dim(),
                    ]))
                }
            })
            .collect();
        Widget::render(List::new(items), chunks[1], frame.buffer);

        if let Some(err) = &self.error_message {
            Widget::render(
                Paragraph::new(Line::from(err.as_str().red())),
                chunks[2],
                frame.buffer,
            );
        }
    }

    fn render_validating(&self, frame: &mut Frame, area: Rect) {
        Widget::render(
            Paragraph::new("Verifying connection..."),
            area,
            frame.buffer,
        );
    }

    fn render_model_select(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::vertical([Constraint::Length(2), Constraint::Min(0)]).split(area);

        Widget::render(Paragraph::new("Select a model:"), chunks[0], frame.buffer);

        let items: Vec<ListItem> = self
            .available_models
            .iter()
            .enumerate()
            .map(|(i, model)| {
                if i == self.selected_model_index {
                    ListItem::new(Line::from(vec!["> ".cyan(), model.as_str().into()]))
                } else {
                    ListItem::new(Line::from(format!("  {model}")))
                }
            })
            .collect();
        Widget::render(List::new(items), chunks[1], frame.buffer);
    }

    fn render_summary(&self, frame: &mut Frame, area: Rect) {
        let lines = vec![
            Line::from("Setup complete!".bold()),
            Line::from(""),
            Line::from(vec!["  Region: ".dim(), self.selected_region().into()]),
            Line::from(vec!["  Model:  ".dim(), self.selected_model().into()]),
            Line::from(""),
            Line::from("Press Enter to start.".dim()),
        ];
        Widget::render(Paragraph::new(lines), area, frame.buffer);
    }

    fn handle_key(&mut self, key: KeyEvent) {
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            self.step = WizardStep::Done;
            self.quit = true;
            return;
        }
        if key.code == KeyCode::Esc {
            self.step = WizardStep::Done;
            self.quit = true;
            return;
        }

        match &self.step {
            WizardStep::AuthMethod => self.handle_auth_method(key),
            WizardStep::ApiKeyEntry => self.handle_api_key_entry(key),
            WizardStep::RegionSelect => self.handle_region_select(key),
            WizardStep::ModelSelect => self.handle_model_select(key),
            WizardStep::Summary => self.handle_summary(key),
            _ => {}
        }
    }

    fn handle_auth_method(&mut self, key: KeyEvent) {
        if key.code == KeyCode::Enter {
            self.step = WizardStep::ApiKeyEntry;
        }
    }

    fn handle_api_key_entry(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Enter => {
                if self.api_key.trim().is_empty() {
                    self.error_message = Some("API key cannot be empty.".into());
                } else {
                    self.error_message = None;
                    self.step = WizardStep::RegionSelect;
                }
            }
            KeyCode::Backspace => {
                self.api_key.pop();
            }
            KeyCode::Char(c) => {
                self.api_key.push(c);
            }
            _ => {}
        }
    }

    fn handle_region_select(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Up => {
                if self.selected_region_index > 0 {
                    self.selected_region_index -= 1;
                }
            }
            KeyCode::Down => {
                if self.selected_region_index < REGIONS.len() - 1 {
                    self.selected_region_index += 1;
                }
            }
            KeyCode::Enter => {
                self.error_message = None;
                self.step = WizardStep::Validating;
            }
            _ => {}
        }
    }

    fn handle_model_select(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Up => {
                if self.selected_model_index > 0 {
                    self.selected_model_index -= 1;
                }
            }
            KeyCode::Down => {
                if self.selected_model_index < self.available_models.len().saturating_sub(1) {
                    self.selected_model_index += 1;
                }
            }
            KeyCode::Enter => {
                self.step = WizardStep::Summary;
            }
            _ => {}
        }
    }

    fn handle_summary(&mut self, key: KeyEvent) {
        if key.code == KeyCode::Enter {
            self.step = WizardStep::Done;
        }
    }
}

pub async fn run_wizard<B: Backend + Write>(
    terminal: &mut Terminal<B>,
) -> Result<WizardResult, Box<dyn std::error::Error>> {
    // Enter alternate screen and set viewport so the wizard renders visibly.
    let _ = execute!(
        terminal.backend_mut(),
        crossterm::terminal::EnterAlternateScreen
    );
    if let Ok(size) = terminal.size() {
        terminal.set_viewport_area(ratatui::layout::Rect::new(0, 0, size.width, size.height));
    }
    let _ = terminal.clear();

    let mut wizard = BedrockSetupWizard::new();

    // Check if env var already has a key
    if let Ok(key) = std::env::var("AWS_BEARER_TOKEN_BEDROCK")
        && !key.trim().is_empty()
    {
        wizard.api_key = key;
        wizard.env_key_detected = true;
        wizard.step = WizardStep::RegionSelect;
    }

    loop {
        terminal.draw(|frame| wizard.render(frame))?;

        if wizard.step == WizardStep::Validating {
            match validation::validate_and_discover_models(
                &wizard.api_key,
                wizard.selected_region(),
            )
            .await
            {
                Ok(result) => {
                    wizard.available_models = result.models;
                    if let Some(idx) = wizard
                        .available_models
                        .iter()
                        .position(|m| m == "deepseek.v3.2")
                    {
                        wizard.selected_model_index = idx;
                    }
                    wizard.step = WizardStep::ModelSelect;
                }
                Err(err) => {
                    wizard.error_message = Some(err);
                    wizard.step = WizardStep::RegionSelect;
                }
            }
            continue;
        }

        if wizard.step == WizardStep::Done {
            break;
        }

        if event::poll(Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(key) => wizard.handle_key(key),
                Event::Paste(text) => {
                    if wizard.step == WizardStep::ApiKeyEntry {
                        wizard.api_key.push_str(text.trim());
                    }
                }
                _ => {}
            }
        }
    }

    // Leave alternate screen so the normal TUI can re-enter it.
    let _ = execute!(
        terminal.backend_mut(),
        crossterm::terminal::LeaveAlternateScreen
    );

    if wizard.quit {
        return Err("Setup cancelled by user.".into());
    }

    let region = wizard.selected_region().to_string();
    let model = wizard.selected_model().to_string();
    let discovered_models = wizard.available_models.clone();

    Ok(WizardResult {
        api_key: wizard.api_key,
        region,
        model,
        discovered_models,
    })
}

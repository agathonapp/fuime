import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = [
    // Slides
    'home',
    'wizard',
    'answer',
    // Wizard slide question targets
    'question',
    'yes',
    'no',
    // Wizard slide answer targets
    'answerText',
    'answerCTA',
    'learnMore',
    'wiseAnswerNote',
  ]

  static values = {
    ach: String,
    check: String,
    wire: String,
    wise: String,
  }

  static questions = [
    {
      id: 1,
      question: 'Does your recipient live within the US?',
      yes: 2,
      no: 3,
    },
    {
      id: 2,
      question: 'Do you have their account & routing number?',
      yes: {
        type: 'ACH transfer',
      },
      no: {
        type: 'Mailed check',
      },
    },
    {
      id: 3,
      question: 'Is your transfer amount over $500?',
      yes: {
        type: 'International wire',
      },
      no: {
        type: 'Wise transfer',
      },
    },
  ]

  showWizard = () => {
    this.homeTarget.hidden = true
    this.answerTarget.hidden = true
    this.wizardTarget.hidden = false
    this.renderQuestion(1)
  }

  hideWizard = () => {
    this.homeTarget.hidden = false
    this.answerTarget.hidden = true
    this.wizardTarget.hidden = true
  }

  reset = () => {
    this.hideWizard()
    this.showWizard()
  }

  renderQuestion = payload => {
    if (typeof payload === 'number') {
      const question = this.constructor.questions.find(q => q.id === payload)
      this.questionTarget.innerHTML = question.question

      this.yesClickHandler = () => this.renderQuestion(question.yes)
      this.noClickHandler = () => this.renderQuestion(question.no)
    } else {
      this.answerTextTarget.innerHTML = payload.type
      this.answerCTATarget.dataset.answer = payload.type

      // The per-answer `link` values were help.hcb.hackclub.com articles —
      // Hack Club's help centre, documenting HCB's transfer products — so they
      // were removed. Hide the "learn more" affordance rather than render an
      // `href="undefined"`; restore it when Fuime has its own docs.
      if (payload.link) {
        this.learnMoreTarget.href = payload.link
        this.learnMoreTarget.hidden = false
      } else {
        this.learnMoreTarget.hidden = true
      }

      this.answerTarget.hidden = false
      this.wizardTarget.hidden = true

      this.wiseAnswerNoteTarget.hidden = payload.type !== 'Wise transfer'
    }
  }

  showAnswer = event => {
    const answer = event.target.dataset.answer
    let value = ''
    if (answer == 'ACH transfer') value = 'ach'
    if (answer == 'Mailed check') value = 'check'
    if (answer == 'International wire') value = 'wire'
    if (answer == 'Wise transfer') value = 'wise'

    window.Turbo.visit(this[`${value}Value`])
  }
}
